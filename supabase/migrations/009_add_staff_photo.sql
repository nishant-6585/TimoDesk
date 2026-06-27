-- Migration 009: Display photo for enrolled staff
--
-- Adds a non-biometric DISPLAY thumbnail for staff, shown in the robot Gallery
-- and the web admin staff list. This is a small cropped face JPEG kept ONLY for
-- UI display — it is NOT used for recognition (that's the irreversible 128-dim
-- embedding in staff_face_embedding). Stored in a PRIVATE Storage bucket and
-- served via short-lived signed URLs so face images are never publicly exposed.

-- 1. Pointer to the thumbnail object in Storage (e.g. '<staff_uuid>.jpg').
ALTER TABLE staff ADD COLUMN IF NOT EXISTS photo_path text;
COMMENT ON COLUMN staff.photo_path IS
  'Storage object path (bucket: staff-photos) for the staff display thumbnail. UI only — not biometric, not used for matching. Null = render initials.';

-- 2. Private bucket for the thumbnails. private (public=false) so access is only
--    via service-role uploads + signed URLs minted by the spine.
INSERT INTO storage.buckets (id, name, public)
VALUES ('staff-photos', 'staff-photos', false)
ON CONFLICT (id) DO NOTHING;

-- No RLS policies on storage.objects for this bucket: the spine accesses it with
-- the service-role key (which bypasses RLS) for both upload and signed-URL minting.
-- Clients never touch the bucket directly — they only receive signed URLs.
