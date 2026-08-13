-- 020 (renumbered from 015 — version collided with 015_fix_match_kb_chunk_threshold):
-- optional per-point arrival announcement.
-- Spoken by the robot's voice agent when it reaches the point; when NULL the
-- apps fall back to a phrase generated from the point name.
alter table public.nav_points
  add column if not exists arrival_text text;
