import { describe, it, expect } from 'vitest';
import { staffToKbText } from '../src/services/kb-staff';

describe('staffToKbText', () => {
  it('renders name, role, type, phone, and desk when all present', () => {
    const text = staffToKbText({
      id: 'a1',
      full_name: 'Saravan',
      role: 'IT',
      person_type: 'Employee',
      phone: '9360833622',
      desk_x: 0.56,
      desk_y: 0.27,
    });
    expect(text).toContain('Saravan');
    expect(text).toContain('IT');
    expect(text).toContain('Employee');
    expect(text).toContain('9360833622');
    expect(text.toLowerCase()).toContain('desk'); // navigable desk mention
  });

  it('omits phone and desk gracefully when missing/null', () => {
    const text = staffToKbText({
      id: 'b2',
      full_name: 'David',
      role: 'E-Commerce Executive',
      person_type: 'Employee',
      phone: null,
      desk_x: null,
      desk_y: null,
    });
    expect(text).toContain('David');
    expect(text).toContain('E-Commerce Executive');
    expect(text).not.toContain('phone number'); // no phone line
    expect(text.toLowerCase()).not.toContain('saved desk'); // no desk line
  });

  it('does not claim a desk when only one coordinate is present', () => {
    const text = staffToKbText({
      id: 'c3',
      full_name: 'Srishti',
      role: 'Sales',
      phone: '9980305364',
      desk_x: 1.2,
      desk_y: null,
    });
    expect(text.toLowerCase()).not.toContain('saved desk');
    expect(text).toContain('9980305364');
  });
});
