/**
 * kb-providers.test.ts — 3rd-party KB sources: file-backed registry CRUD,
 * token redaction, priority ordering, the query chain (first usable answer
 * wins, failures skipped), and the LOCAL-FIRST ask integration in rag.ts.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { SupabaseClient } from '@supabase/supabase-js';
import {
  KbProviderRegistry,
  queryProviders,
  validateProvider,
  KbProvider,
} from '../src/services/kb-providers';
import { askQuestion, isLocalMiss, LOCAL_MISS_THRESHOLD } from '../src/services/rag';
import { KbHit } from '../src/services/kb';

const fakeSupabase = {} as SupabaseClient;

let dir: string;
let filePath: string;

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'kb-providers-'));
  filePath = join(dir, 'kb-providers.json');
});

afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('KbProviderRegistry', () => {
  it('adds, persists, redacts tokens, and reloads from disk', () => {
    const reg = new KbProviderRegistry(filePath);
    const p = reg.add({
      name: 'elevenlabs',
      url: 'https://api.example.com/kb/ask',
      authorization_token: 'secret-token',
      description: 'Hosted agent KB',
    });
    expect(p.has_token).toBe(true);
    expect(JSON.stringify(p)).not.toContain('secret-token');

    const reloaded = new KbProviderRegistry(filePath);
    expect(reloaded.list()).toHaveLength(1);
    expect(reloaded.enabledInOrder()[0].authorization_token).toBe('secret-token');
  });

  it('auto-assigns ascending priorities and orders by priority', () => {
    const reg = new KbProviderRegistry(filePath);
    reg.add({ name: 'first', url: 'https://a.example.com' });
    reg.add({ name: 'second', url: 'https://b.example.com' });
    reg.add({ name: 'urgent', url: 'https://c.example.com', priority: 0 });
    const order = reg.enabledInOrder().map(p => p.name);
    expect(order).toEqual(['first', 'urgent', 'second'].sort((a, b) => {
      const prio: Record<string, number> = { first: 0, urgent: 0, second: 1 };
      return prio[a] - prio[b] || a.localeCompare(b);
    }));
    // Priority ties break alphabetically; explicit priorities win over insertion order.
    expect(order[order.length - 1]).toBe('second');
  });

  it('update patches priority/enabled and clears tokens with empty string', () => {
    const reg = new KbProviderRegistry(filePath);
    reg.add({ name: 'kb1', url: 'https://a.example.com', authorization_token: 't' });
    reg.update('kb1', { priority: 7, enabled: false });
    expect(reg.list()[0].priority).toBe(7);
    expect(reg.enabledInOrder()).toHaveLength(0);
    reg.update('kb1', { authorization_token: '' });
    expect(reg.list()[0].has_token).toBe(false);
  });

  it('rejects duplicates, bad names, bad URLs, bad priorities', () => {
    const reg = new KbProviderRegistry(filePath);
    reg.add({ name: 'kb1', url: 'https://a.example.com' });
    expect(() => reg.add({ name: 'KB1', url: 'https://b.example.com' })).toThrow(/already exists/);
    expect(validateProvider({ name: 'bad name!', url: 'https://x.example.com' })).toMatch(/name/);
    expect(validateProvider({ name: 'ok', url: 'ftp://x' })).toMatch(/http/);
    expect(validateProvider({ name: 'ok', url: 'https://x.example.com', priority: -1 })).toMatch(/priority/);
    expect(() => reg.remove('nope')).toThrow(/not found/);
  });
});

function provider(name: string, priority: number): KbProvider {
  return { name, type: 'http', url: `https://${name}.example.com/ask`, priority, enabled: true };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status });
}

describe('queryProviders', () => {
  it('returns the first usable answer in order and skips failures', async () => {
    const calls: string[] = [];
    const fetchFn = (async (url: RequestInfo | URL) => {
      calls.push(String(url));
      if (String(url).includes('broken')) throw new Error('down');
      if (String(url).includes('empty')) return jsonResponse({ answer: '' });
      return jsonResponse({ answer: 'From the corporate KB.' });
    }) as typeof fetch;

    const result = await queryProviders(
      [provider('broken', 0), provider('empty', 1), provider('works', 2), provider('never', 3)],
      'when was xboom founded?',
      { fetchFn }
    );
    expect(result).toEqual({ answer: 'From the corporate KB.', provider: 'works' });
    expect(calls).toHaveLength(3); // 'never' not consulted after a hit
  });

  it('sends the bearer token and returns null when nobody answers', async () => {
    let seenAuth: string | null = null;
    const fetchFn = (async (_url: RequestInfo | URL, init?: RequestInit) => {
      seenAuth = (init?.headers as Record<string, string>)?.Authorization ?? null;
      return jsonResponse({}, 500);
    }) as typeof fetch;
    const p = { ...provider('kb', 0), authorization_token: 'tok123' };
    expect(await queryProviders([p], 'q', { fetchFn })).toBeNull();
    expect(seenAuth).toBe('Bearer tok123');
  });
});

function hit(similarity: number, isFaq = false): KbHit {
  return { id: 'x', content: 'chunk content', is_faq: isFaq, similarity, topic: null, source: null } as unknown as KbHit;
}

describe('local-first ask chain', () => {
  it('isLocalMiss: null or weak similarity is a miss', () => {
    expect(isLocalMiss(null)).toBe(true);
    expect(isLocalMiss(LOCAL_MISS_THRESHOLD - 0.01)).toBe(true);
    expect(isLocalMiss(LOCAL_MISS_THRESHOLD)).toBe(false);
  });

  it('does NOT consult providers when local context is decent', async () => {
    let providersAsked = false;
    const answer = await askQuestion(fakeSupabase, 'q', {
      search: async () => [hit(0.7)],
      generate: async () => 'Grounded local answer.',
      askProviders: async () => ((providersAsked = true), { answer: 'external', provider: 'x' }),
    });
    expect(answer.source).toBe('claude');
    expect(providersAsked).toBe(false);
  });

  it('falls through to providers on a local miss', async () => {
    const answer = await askQuestion(fakeSupabase, 'q', {
      search: async () => [hit(0.2)],
      generate: async () => {
        throw new Error('generate must not run when a provider answered');
      },
      askProviders: async () => ({ answer: 'HQ says: founded in 2020.', provider: 'hq-faq' }),
    });
    expect(answer.source).toBe('provider');
    expect(answer.provider).toBe('hq-faq');
    expect(answer.answer).toContain('founded in 2020');
  });

  it('uses grounded Claude when providers have nothing either', async () => {
    const answer = await askQuestion(fakeSupabase, 'q', {
      search: async () => [],
      generate: async () => "I'll connect you to a team member.",
      askProviders: async () => null,
    });
    expect(answer.source).toBe('claude');
  });

  it('FAQ fast-path still wins over everything', async () => {
    const answer = await askQuestion(fakeSupabase, 'q', {
      search: async () => [hit(0.95, true)],
      generate: async () => {
        throw new Error('no LLM on FAQ hit');
      },
      askProviders: async () => {
        throw new Error('no providers on FAQ hit');
      },
    });
    expect(answer.source).toBe('kb');
  });
});
