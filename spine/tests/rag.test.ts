/**
 * tests/rag.test.ts — voice-brain orchestration (T6 fast-path + T7 fallback).
 * FAQ fast-path is a pure decision; askQuestion routes to KB or Claude. Both are
 * tested with injected deps so no Voyage/Anthropic calls happen.
 */

import { describe, it, expect, vi } from 'vitest';
import {
  pickFaqAnswer,
  askQuestion,
  isAuthoritative,
  FAQ_FAST_PATH_THRESHOLD,
  Answer,
} from '../src/services/rag';
import { KbHit } from '../src/services/kb';

const hit = (over: Partial<KbHit>): KbHit => ({
  id: 'k1', topic: 'company', content: 'xboom builds robots.', is_faq: false, similarity: 0.5, ...over,
});

const supabase = {} as any; // unused when deps are injected

describe('pickFaqAnswer', () => {
  it('returns the top hit when it is an FAQ above threshold', () => {
    const top = hit({ is_faq: true, similarity: 0.9 });
    expect(pickFaqAnswer([top, hit({})])).toBe(top);
  });

  it('returns null when the top hit is not an FAQ', () => {
    expect(pickFaqAnswer([hit({ is_faq: false, similarity: 0.99 })])).toBeNull();
  });

  it('returns null when the top FAQ is below threshold', () => {
    expect(pickFaqAnswer([hit({ is_faq: true, similarity: FAQ_FAST_PATH_THRESHOLD - 0.01 })])).toBeNull();
  });

  it('returns null on an empty result set', () => {
    expect(pickFaqAnswer([])).toBeNull();
  });
});

describe('isAuthoritative — local KB wins on overlap', () => {
  it('a grounded local / provider answer is authoritative (agent prefers it)', () => {
    expect(isAuthoritative('kb')).toBe(true);
    expect(isAuthoritative('claude')).toBe(true);
    expect(isAuthoritative('provider')).toBe(true);
  });
  it('a local miss (handoff) is NOT authoritative — agent may use its own KB', () => {
    expect(isAuthoritative('handoff')).toBe(false);
  });
});

describe('askQuestion', () => {
  it('takes the FAQ fast-path (source=kb) and never calls Claude', async () => {
    const faq = hit({ content: 'We are open 9-6, Mon-Fri.', is_faq: true, similarity: 0.92 });
    const generate = vi.fn();
    const result: Answer = await askQuestion(supabase, 'what are your hours?', {
      search: async () => [faq],
      generate,
    });
    expect(result).toMatchObject({ answer: faq.content, source: 'kb', similarity: 0.92 });
    expect(generate).not.toHaveBeenCalled();
  });

  it('falls through to Claude (source=claude) on a KB miss', async () => {
    const weak = hit({ is_faq: false, similarity: 0.4 });
    const generate = vi.fn(async () => 'Let me connect you to a team member.');
    const result = await askQuestion(supabase, 'do you do underwater drones?', {
      search: async () => [weak],
      generate,
    });
    expect(result).toMatchObject({ answer: 'Let me connect you to a team member.', source: 'claude', similarity: 0.4 });
    expect(generate).toHaveBeenCalledWith('do you do underwater drones?', [weak]);
  });

  it('still answers via Claude when the KB is empty, tagged handoff (similarity null)', async () => {
    const generate = vi.fn(async () => "I'll connect you to someone who can help.");
    const result = await askQuestion(supabase, 'anything?', { search: async () => [], generate });
    // Claude still speaks the line, but an empty KB means it promised a human —
    // 'handoff' is what makes that promise visible so a person is actually paged.
    expect(result).toMatchObject({ source: 'handoff', similarity: null });
    expect(generate).toHaveBeenCalledWith('anything?', []);
  });

  it('tags a below-threshold local miss as handoff, not claude', async () => {
    const weak = hit({ is_faq: false, similarity: 0.2 });
    const generate = vi.fn(async () => 'Let me connect you to a team member.');
    const result = await askQuestion(supabase, 'what does it cost?', {
      search: async () => [weak],
      generate,
      askProviders: async () => null, // no 3rd-party KB could answer either
    });
    expect(result.source).toBe('handoff');
  });

  it('keeps source=claude when context was good enough to ground an answer', async () => {
    const solid = hit({ is_faq: false, similarity: 0.71 });
    const generate = vi.fn(async () => 'We build land, air and water robots.');
    const result = await askQuestion(supabase, 'what do you build?', {
      search: async () => [solid],
      generate,
    });
    // Grounded answer — nobody needs paging.
    expect(result.source).toBe('claude');
  });
});
