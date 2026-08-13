-- 022 (renumbered from unapplied 019): Entra ID photo → face-embedding sync
-- (Phases 1-2 of the Entra plan).
--
-- The directory sync (021) mirrors users; this adds what the PHOTO pipeline
-- needs:
--
--   • staff.entra_photo_etag     — Graph @odata.mediaEtag of the last photo we
--                                  embedded; unchanged etag = skip the download.
--   • staff.entra_photo_status   — outcome of the last photo pass, so the admin
--                                  can see exactly who is recognizable and who
--                                  needs an on-robot top-up enrollment:
--                                  ok | none | no_consent | rejected_quality |
--                                  rejected_multi_face | collision | error | purged
--   • staff.entra_synced_at      — last time the sync touched this row.
--   • staff.entra_deactivated_at — when the sync deactivated the row (account
--                                  disabled/vanished in Graph); drives the
--                                  offboarding purge of entra-photo embeddings
--                                  after ENTRA_OFFBOARD_PURGE_DAYS.
--   • entra_sync_state           — single-row-per-key state (the /users/delta
--                                  deltaLink) so recurring syncs are incremental.
--
-- Embeddings created from directory photos carry consent_ref
-- 'entra-photo:<etag>' — the offboarding/consent-revocation purges delete ONLY
-- those rows; on-robot enrollments (other consent_refs) stay a human decision.

alter table staff add column if not exists entra_photo_etag text;
alter table staff add column if not exists entra_photo_status text;
alter table staff add column if not exists entra_synced_at timestamptz;
alter table staff add column if not exists entra_deactivated_at timestamptz;

comment on column staff.entra_photo_etag is
  'Graph @odata.mediaEtag of the last directory photo embedded for this staff. NULL = never fetched.';
comment on column staff.entra_photo_status is
  'Last Entra photo-sync outcome: ok | none | no_consent | rejected_quality | rejected_multi_face | collision | error | purged.';
comment on column staff.entra_synced_at is
  'Last time the Entra sync touched this row.';
comment on column staff.entra_deactivated_at is
  'When the Entra sync deactivated this row (Graph account disabled/removed). Drives the offboarding embedding purge.';

create table if not exists entra_sync_state (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

comment on table entra_sync_state is
  'Entra sync cursor state (e.g. the /users/delta deltaLink). Written by the spine (service role) only.';

-- RLS: service-role only (the spine). No anon/authenticated access — admins see
-- sync state through the spine''s GET /entra/status, never directly.
alter table entra_sync_state enable row level security;
