import { describe, it, expect } from 'vitest';
import { staffDeskToNavPoint, STAFF_DESK_ID_PREFIX } from '../src/services/staff-desks';

describe('staffDeskToNavPoint', () => {
  it('maps a staff desk to a NavPoint-shaped point (matches NavPoint.fromJson)', () => {
    const p = staffDeskToNavPoint({
      id: 'abc', full_name: 'Narasimha',
      desk_x: 2.802335, desk_y: -0.086, desk_z: 0, desk_rotation: -69.21,
    });
    expect(p.id).toBe('staff-desk:abc');
    expect(String(p.id).startsWith(STAFF_DESK_ID_PREFIX)).toBe(true);
    expect(p.name).toBe('Narasimha');           // so "take me to Narasimha" matches
    expect(p.x).toBe(2.802335);
    expect(p.y).toBe(-0.086);
    expect(p.rotation).toBe(-69.21);
    expect(p.kind).toBe('staff_desk');
  });

  it('defaults null z/rotation to 0 and trims the name', () => {
    const p = staffDeskToNavPoint({
      id: 'x', full_name: '  pawan  ', desk_x: 1, desk_y: 2, desk_z: null, desk_rotation: null,
    });
    expect(p.name).toBe('pawan');
    expect(p.z).toBe(0);
    expect(p.rotation).toBe(0);
    expect(p.description).toBe("pawan's desk");
  });
});
