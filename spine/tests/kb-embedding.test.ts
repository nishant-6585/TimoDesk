/**
 * tests/kb-embedding.test.ts — Voyage embedding wrapper (T5).
 * Covers request shape (asymmetric input_type + dimension), success, and errors.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { embedText, KB_EMBED_DIM } from '../src/services/kb-embedding';

const ORIG_ENV = { ...process.env };
const VEC = Array.from({ length: KB_EMBED_DIM }, () => 0.1);

function mockFetch(status: number, body: unknown) {
  const fn = vi.fn(async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  }));
  // @ts-expect-error override global fetch in test
  global.fetch = fn;
  return fn;
}

beforeEach(() => {
  process.env.VOYAGE_API_KEY = 'pa-test';
  delete process.env.VOYAGE_MODEL;
});
afterEach(() => {
  process.env = { ...ORIG_ENV };
  vi.restoreAllMocks();
});

describe('embedText', () => {
  it('throws a clear error when VOYAGE_API_KEY is unset', async () => {
    delete process.env.VOYAGE_API_KEY;
    await expect(embedText('hi', 'query')).rejects.toThrow(/VOYAGE_API_KEY not set/);
  });

  it('sends the right model, input_type, and dimension, and returns the vector', async () => {
    const f = mockFetch(200, { data: [{ embedding: VEC }] });
    const out = await embedText('who is xboom?', 'query');
    expect(out).toHaveLength(KB_EMBED_DIM);
    const [url, opts] = f.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://api.voyageai.com/v1/embeddings');
    expect((opts.headers as Record<string, string>).Authorization).toBe('Bearer pa-test');
    const sent = JSON.parse(opts.body as string);
    expect(sent).toMatchObject({ input: 'who is xboom?', model: 'voyage-3.5', input_type: 'query', output_dimension: KB_EMBED_DIM });
  });

  it('throws when the provider rejects the request', async () => {
    mockFetch(401, { detail: 'bad key' });
    await expect(embedText('x', 'document')).rejects.toThrow(/voyage embed failed: 401/);
  });

  it('throws on a dimension mismatch (guards against a model/schema drift)', async () => {
    mockFetch(200, { data: [{ embedding: [0.1, 0.2, 0.3] }] });
    await expect(embedText('x', 'document')).rejects.toThrow(/returned 3 dims, expected 1024/);
  });
});
