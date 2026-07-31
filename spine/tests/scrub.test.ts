/**
 * tests/scrub.test.ts — conversation transcript PII redaction.
 *
 * The `conversation` table's contract requires PII-scrubbed transcripts; before
 * this, nothing scrubbed anywhere. Covers what MUST be redacted, what must
 * SURVIVE (structure + analytics value), and the malformed-input guards.
 */

import { describe, it, expect } from 'vitest';
import { scrubText, scrubTranscript, scrubValue } from '../src/services/scrub';

describe('scrubText', () => {
  it('redacts email addresses', () => {
    expect(scrubText('mail me at priya.n@xboom.in please')).toBe('mail me at [email] please');
  });

  it('redacts phone numbers in common spoken/typed shapes', () => {
    expect(scrubText('call +91 98123 45678')).toContain('[phone]');
    expect(scrubText('my number is 9812345678')).toContain('[phone]');
    expect(scrubText('reach me on 080-2345-6789')).toContain('[phone]');
    expect(scrubText('call +91 98123 45678')).not.toMatch(/\d{5}/);
  });

  it('redacts an email before its digits can be phone-matched', () => {
    // Rule order matters — a naive phone pass would eat "1234567890" out of the
    // address and leave a mangled half-address behind.
    const out = scrubText('write to user1234567890@example.com');
    expect(out).toBe('write to [email]');
  });

  it('redacts long bare digit runs (card/ID shaped)', () => {
    expect(scrubText('4111111111111111')).toBe('[number]');
  });

  it('leaves ordinary conversation untouched', () => {
    const s = 'I am here to see Priya about the Q3 robotics demo.';
    expect(scrubText(s)).toBe(s);
  });

  it('does not redact small numbers that carry meaning', () => {
    // Room numbers, floors, times — analytics depends on these surviving.
    expect(scrubText('meeting room 3 on floor 2 at 4 pm')).toBe('meeting room 3 on floor 2 at 4 pm');
  });
});

describe('scrubValue / scrubTranscript', () => {
  it('scrubs nested strings while preserving structure', () => {
    const entry = {
      role: 'user',
      text: 'call me on 9812345678',
      meta: { kind: 'checkin_turn', detail: 'a@b.com', t: 1234 },
    };
    const out = scrubValue(entry) as typeof entry;
    expect(out.role).toBe('user');
    expect(out.meta.kind).toBe('checkin_turn');
    expect(out.meta.t).toBe(1234); // numbers untouched
    expect(out.text).toContain('[phone]');
    expect(out.meta.detail).toBe('[email]');
  });

  it('scrubs every entry in a transcript array', () => {
    const out = scrubTranscript([
      { role: 'user', text: 'a@b.com' },
      { role: 'agent', text: 'no pii here' },
    ]) as Array<{ text: string }>;
    expect(out[0].text).toBe('[email]');
    expect(out[1].text).toBe('no pii here');
  });

  it('passes non-string primitives through unchanged', () => {
    expect(scrubValue(42)).toBe(42);
    expect(scrubValue(null)).toBeNull();
    expect(scrubValue(true)).toBe(true);
  });

  it('stops at the depth cap instead of recursing forever', () => {
    // Deeply nested payload must not spin the reception line.
    let deep: unknown = 'a@b.com';
    for (let i = 0; i < 30; i++) deep = { next: deep };
    expect(() => scrubValue(deep)).not.toThrow();
  });
});
