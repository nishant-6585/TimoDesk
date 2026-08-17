-- Migration 019: KB auto-sync sources
--
-- Persists each ingested URL / website-crawl as a first-class SOURCE so the KB
-- can be re-synced (manual "Sync now" or on a schedule) instead of being a
-- one-time snapshot. Before this, crawl jobs lived only in memory and there was
-- no record of what was ingested from where — so nothing could be refreshed.
--
-- A source_id FK on kb_chunk is the clean dedup key: a re-sync deletes all of a
-- source's chunks by source_id, then re-ingests — so re-crawling never
-- duplicates (the same delete-then-reingest fix kb-staff uses via source prefix).
--
-- Brokered through the spine (service-role) like nav_points/voice_commands
-- post-017: RLS stays closed; clients read/write via /kb/sources HTTP routes.

create table if not exists kb_source (
  id                  uuid primary key default gen_random_uuid(),
  kind                text not null,                    -- 'url' | 'crawl'
  url                 text not null,
  topic               text,
  max_pages           integer,                          -- crawl page cap (null for 'url')
  auto_sync           boolean not null default false,   -- periodic re-sync enabled?
  sync_interval_hours integer not null default 24,      -- cadence when auto_sync on
  last_synced_at      timestamptz,
  last_status         text,                             -- 'ok' | 'error' | 'running'
  last_error          text,
  chunk_count         integer not null default 0,       -- chunks written by the last sync
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (kind, url)                                     -- one managed source per url+kind
);

create index if not exists kb_source_autosync_idx
  on kb_source (auto_sync, last_synced_at);

alter table kb_source enable row level security;
-- Spine (service-role) bypasses RLS; no anon/authenticated policy on purpose —
-- sources are managed only through the spine's authenticated /kb/sources routes.

create or replace function kb_source_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists kb_source_touch on kb_source;
create trigger kb_source_touch
  before update on kb_source
  for each row execute function kb_source_touch_updated_at();

-- Link chunks to their source so a re-sync can delete-by-source cleanly.
-- Nullable: manually-typed text chunks + all pre-existing rows have no source.
alter table kb_chunk
  add column if not exists source_id uuid references kb_source(id) on delete cascade;

create index if not exists kb_chunk_source_id_idx on kb_chunk (source_id);
