-- Migration 011: allow the anon role to manage nav_points
--
-- The on-robot Flutter app runs headless on the robot's head and talks to Supabase
-- with the public anon key — there is no login flow on the robot. Migration 010's
-- policies were `TO authenticated`, so the robot (anon) is RLS-blocked: SELECT
-- returns empty and INSERT fails with 42501. The web admin (authenticated session)
-- is unaffected.
--
-- Nav points are non-sensitive map coordinates (no personal/biometric data) used by
-- a trusted device on the office LAN, so we widen the policies to the public role
-- (anon + authenticated). RLS stays ENABLED — this only broadens who the existing
-- allow-all policy applies to. Biometric/visitor tables are untouched.

DROP POLICY IF EXISTS nav_points_select ON nav_points;
CREATE POLICY nav_points_select ON nav_points
  FOR SELECT USING (true);

DROP POLICY IF EXISTS nav_points_write ON nav_points;
CREATE POLICY nav_points_write ON nav_points
  FOR ALL USING (true) WITH CHECK (true);
