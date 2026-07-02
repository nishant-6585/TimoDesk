-- Migration 012: Remote photo capture (F7) — snapshots bucket + actor attribution
--
-- Completes the admin "remote snapshot" feature: an admin taps Snapshot in the
-- app → the spine grabs a JPEG from the robot → uploads it here → inserts a
-- `capture` row → the app Gallery lists it. The `capture` table (002) + its
-- retention trigger (005, 30d for admin_snapshot) already exist; this migration
-- adds the two missing pieces: a place to store the bytes, and a way to record
-- who took the shot.

-- 1. Private bucket for admin snapshots. Same posture as staff-photos (009):
--    private (public=false) — the spine uploads with the service-role key and
--    mints short-lived signed URLs; clients never touch the bucket directly.
INSERT INTO storage.buckets (id, name, public)
VALUES ('snapshots', 'snapshots', false)
ON CONFLICT (id) DO NOTHING;

-- 2. Attribution. `capture.taken_by` is a FK to staff(id), but admins authenticate
--    as Supabase auth users with no staff<->auth link yet, so we cannot put the
--    auth user id there without risking a FK violation. `actor` is a free-text
--    record of who triggered the capture (auth user id, 'kiosk-robot', or null for
--    autonomous patrol/intrusion frames). taken_by stays reserved for the future
--    staff<->auth link.
ALTER TABLE capture ADD COLUMN IF NOT EXISTS actor text;
COMMENT ON COLUMN capture.actor IS
  'Who triggered the capture: Supabase auth user id / ''kiosk-robot'' / null for autonomous. Free-text attribution; taken_by (staff FK) is reserved for a future staff<->auth link.';

-- No RLS policies on storage.objects for the snapshots bucket: the spine uses the
-- service-role key (bypasses RLS) for upload + signed-URL minting, exactly like
-- staff-photos. The `capture` table itself already has admin RLS (003).
