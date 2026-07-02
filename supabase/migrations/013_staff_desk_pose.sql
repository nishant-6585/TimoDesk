-- Migration 013: staff desk/location pose (navigate-to-desk groundwork, #71)
--
-- Records WHERE a staff member sits, captured during (or after) face enrollment
-- via the SDK getPosition() SLAM pose {x, y, z, rotation} — the same shape as
-- nav_points and the `navi` intent. This lets a later feature send Timo to
-- "<person>'s desk" to announce a visitor, instead of hunting for a moving face.
--
-- Stored inline on `staff` (not a nav_points link) so it's self-contained and
-- feeds the existing navi intent directly. Null desk_x/desk_y = no desk captured.

ALTER TABLE staff ADD COLUMN IF NOT EXISTS desk_x            double precision;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS desk_y            double precision;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS desk_z            double precision;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS desk_rotation     double precision;
ALTER TABLE staff ADD COLUMN IF NOT EXISTS desk_captured_at  timestamptz;

COMMENT ON COLUMN staff.desk_x IS
  'Desk SLAM pose (with desk_y/z/rotation) captured via getPosition(); tied to the loaded robot map. Null = no desk captured. Feeds the navi intent for navigate-to-desk (#71).';
