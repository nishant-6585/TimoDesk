import { describe, it, expect } from 'vitest';
import { voiceCommandInsert, voiceCommandPatch } from '../src/handlers/voice-commands';

describe('voiceCommandInsert', () => {
  it('accepts a valid command and normalizes phrases', () => {
    const r = voiceCommandInsert({
      intent: 'patrol',
      label: 'Patrol rounds',
      skill: 'navigation',
      example_phrases: ['  Start Patrol ', 'make your rounds', ''],
      confirm: true,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.row.example_phrases).toEqual(['start patrol', 'make your rounds']);
      expect(r.row.confirm).toBe(true);
      expect(r.row.enabled).toBe(true); // default
      expect(r.row.tier).toBe('reflex'); // default
    }
  });

  it('rejects a blank intent', () => {
    expect(voiceCommandInsert({ label: 'x', example_phrases: ['a b'] })).toMatchObject({ ok: false });
  });

  it('rejects an empty phrase list — a dead command', () => {
    const r = voiceCommandInsert({ intent: 'patrol', label: 'x', example_phrases: [' ', ''] });
    expect(r.ok).toBe(false);
  });

  it('rejects an unknown skill', () => {
    const r = voiceCommandInsert({ intent: 'x', label: 'x', skill: 'weapons', example_phrases: ['a'] });
    expect(r).toMatchObject({ ok: false });
  });
});

describe('voiceCommandPatch', () => {
  it('allows toggling enabled only', () => {
    const r = voiceCommandPatch({ enabled: false });
    expect(r).toEqual({ ok: true, patch: { enabled: false } });
  });

  it('rejects a blank label', () => {
    expect(voiceCommandPatch({ label: '   ' })).toMatchObject({ ok: false });
  });

  it('rejects an empty patch', () => {
    expect(voiceCommandPatch({})).toMatchObject({ ok: false });
  });

  it('normalizes patched phrases', () => {
    const r = voiceCommandPatch({ example_phrases: ['GO Home', ' dock '] });
    expect(r).toMatchObject({ ok: true, patch: { example_phrases: ['go home', 'dock'] } });
  });
});
