/**
 * services/nav-points.ts — read saved waypoints from Supabase, spine-side.
 *
 * Until now the spine never loaded nav points: every patrol/navi intent carried
 * its points from a client. The after-hours security patrol (F9) has no client —
 * it starts on a timer at 19:00 with nobody logged in — so it needs its own
 * source of truth.
 *
 * 'welcome' points are excluded: that's the idle/home pose, not somewhere worth
 * walking a security route to.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { RobotPosition } from '../types';

export type NavWaypoint = RobotPosition & { name?: string; arrivalText?: string };

/**
 * The 'welcome' point — the robot's home/idle pose. Used as the tour's
 * return-to-base target (F8). Returns null when none is saved.
 */
export async function loadWelcomePoint(supabase: SupabaseClient): Promise<NavWaypoint | null> {
  const { data, error } = await supabase
    .from('nav_points')
    .select('name, x, y, z, rotation, arrival_text')
    .eq('kind', 'welcome')
    .order('sort_order', { ascending: true })
    .limit(1)
    .maybeSingle();

  if (error || !data) {
    if (error) console.error('[nav-points] welcome point load failed:', error.message);
    return null;
  }
  const r = data as {
    name: string; x: number; y: number; z: number | null;
    rotation: number | null; arrival_text: string | null;
  };
  return {
    x: r.x,
    y: r.y,
    z: r.z ?? 0,
    rotation: r.rotation ?? 0,
    name: r.name,
    ...(r.arrival_text ? { arrivalText: r.arrival_text } : {}),
  };
}

export async function loadPatrolWaypoints(supabase: SupabaseClient): Promise<NavWaypoint[]> {
  const { data, error } = await supabase
    .from('nav_points')
    .select('name, x, y, z, rotation, arrival_text, kind, sort_order')
    .eq('kind', 'navigation')
    .order('sort_order', { ascending: true });

  if (error) {
    console.error('[nav-points] load failed:', error.message);
    return [];
  }

  return (data ?? []).map(row => {
    const r = row as {
      name: string; x: number; y: number; z: number | null; rotation: number | null;
    };
    return {
      x: r.x,
      y: r.y,
      z: r.z ?? 0,
      rotation: r.rotation ?? 0,
      name: r.name,
      // arrivalText is deliberately omitted: a security patrol runs at night
      // with nobody to hear it, and announcing each waypoint would only tell an
      // intruder where the robot is.
    };
  });
}
