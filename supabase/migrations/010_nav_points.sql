-- Migration 010: Navigation points (P0 reception parity)
--
-- Named SLAM poses the robot can navigate to (capture-by-driving in the admin →
-- one-tap "send robot to <point>"). Mirrors the vendor Reception app's
-- SettingPointActivity, but stored in Supabase (the vendor keeps them in local
-- SharedPreferences). The pose is captured via the SDK getPosition() →
-- {x, y, z, rotation}; navigation replays it via getAction().navi(json).

CREATE TABLE IF NOT EXISTS nav_points (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  description text,
  x           double precision NOT NULL,
  y           double precision NOT NULL,
  z           double precision NOT NULL DEFAULT 0,
  rotation    double precision NOT NULL DEFAULT 0,
  -- 'navigation' = a destination guests are led to; 'welcome' = the idle/home
  -- point the robot returns to. (Patrol routes will reference these in a later table.)
  kind        text NOT NULL DEFAULT 'navigation' CHECK (kind IN ('navigation', 'welcome')),
  sort_order  int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE nav_points IS
  'Named SLAM poses for autonomous navigation. Pose captured via SDK getPosition(); navigated via getAction().navi(). Tied to the currently-loaded robot map.';

CREATE INDEX IF NOT EXISTS nav_points_kind_idx ON nav_points (kind, sort_order);

-- RLS: authenticated admins manage points; non-negotiable per project convention.
ALTER TABLE nav_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nav_points_select ON nav_points;
CREATE POLICY nav_points_select ON nav_points
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS nav_points_write ON nav_points;
CREATE POLICY nav_points_write ON nav_points
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- keep updated_at fresh
CREATE OR REPLACE FUNCTION set_nav_points_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS nav_points_updated_at ON nav_points;
CREATE TRIGGER nav_points_updated_at BEFORE UPDATE ON nav_points
  FOR EACH ROW EXECUTE FUNCTION set_nav_points_updated_at();
