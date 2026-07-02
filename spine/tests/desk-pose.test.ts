/**
 * tests/desk-pose.test.ts — deskColumns() (staff desk-location capture, #71).
 * Shared by /enroll and PATCH /staff, so its validation is worth pinning down.
 */

import { describe, it, expect } from 'vitest';
import { deskColumns } from '../src/handlers/enroll';

describe('deskColumns', () => {
  it('maps a full pose to desk_* columns and stamps desk_captured_at', () => {
    const cols = deskColumns({ x: 1.5, y: -2.25, z: 0.1, rotation: 90 });
    expect(cols).toMatchObject({ desk_x: 1.5, desk_y: -2.25, desk_z: 0.1, desk_rotation: 90 });
    expect(typeof cols!.desk_captured_at).toBe('string');
  });

  it('defaults z and rotation to 0 when omitted', () => {
    const cols = deskColumns({ x: 1, y: 2 });
    expect(cols).toMatchObject({ desk_x: 1, desk_y: 2, desk_z: 0, desk_rotation: 0 });
  });

  it('returns null for absent or invalid poses (x/y required + finite)', () => {
    expect(deskColumns(undefined)).toBeNull();
    expect(deskColumns(null)).toBeNull();
    // @ts-expect-error missing y
    expect(deskColumns({ x: 1 })).toBeNull();
    expect(deskColumns({ x: NaN, y: 2 })).toBeNull();
    expect(deskColumns({ x: Infinity, y: 2 })).toBeNull();
  });
});
