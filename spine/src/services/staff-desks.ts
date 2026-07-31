/**
 * staff-desks.ts — expose enrolled-staff desk poses (migration 013:
 * desk_x/desk_y/desk_z/desk_rotation) as synthetic, nav_points-shaped points so
 * the robot app displays them on the dashboard, navigates to them on tap, AND
 * voice-matches them ("take me to Narasimha") — all through the EXISTING nav
 * plumbing, no app change. Read-only: the id is prefixed `staff-desk:` so it is
 * never confused with a real nav_points row (POST/PATCH/DELETE won't touch it).
 */

import { SupabaseClient } from '@supabase/supabase-js';

export interface StaffDeskRow {
  id: string;
  full_name: string;
  desk_x: number | null;
  desk_y: number | null;
  desk_z: number | null;
  desk_rotation: number | null;
}

/** Prefix that marks a synthetic staff-desk point (vs a real nav_points id). */
export const STAFF_DESK_ID_PREFIX = 'staff-desk:';

/** One staff desk row → a nav_points-shaped point (matches NavPoint.fromJson). */
export function staffDeskToNavPoint(s: StaffDeskRow): Record<string, unknown> {
  return {
    id: `${STAFF_DESK_ID_PREFIX}${s.id}`,
    name: s.full_name.trim(),
    description: `${s.full_name.trim()}'s desk`,
    x: s.desk_x ?? 0,
    y: s.desk_y ?? 0,
    z: s.desk_z ?? 0,
    rotation: s.desk_rotation ?? 0,
    kind: 'staff_desk',
    // Sort after real nav points so rooms/reception list first, desks after.
    sort_order: 1000,
  };
}

/**
 * All active staff with a captured desk, as nav points. Best-effort: on error
 * returns [] so /nav-points still serves the real points (desks are additive).
 */
export async function staffDeskNavPoints(
  supabase: SupabaseClient
): Promise<Record<string, unknown>[]> {
  const { data, error } = await supabase
    .from('staff')
    .select('id, full_name, desk_x, desk_y, desk_z, desk_rotation')
    .eq('active', true)
    .not('desk_x', 'is', null)
    .not('desk_y', 'is', null);
  if (error) {
    console.error('[nav-points] staff-desk fetch failed (serving nav points only):', error.message);
    return [];
  }
  return (data ?? [])
    .filter((s): s is StaffDeskRow => typeof (s as StaffDeskRow).full_name === 'string' && (s as StaffDeskRow).full_name.trim().length > 0)
    .map(staffDeskToNavPoint);
}
