/**
 * tests/staff.test.ts — GET /staff (enrolled staff list)
 *
 * Covers: embedding counts per staff, and the display-thumbnail mapping —
 * staff with a photo_path get a signed photo_url; staff without one get null.
 */

import { describe, it, expect, vi } from 'vitest';

vi.mock('../src/auth/middleware', () => ({
  authorizeRequest: () => ({ ok: true, userId: 'test-user' }),
}));
vi.mock('../src/supabase/events', () => ({ logEvent: vi.fn(async () => {}) }));

import { handleListStaff } from '../src/handlers/staff';

function makeRes() {
  return {
    statusCode: 0,
    body: '',
    writeHead(status: number) { this.statusCode = status; return this; },
    end(payload?: string) { this.body = payload ?? ''; },
  };
}

// Mock just the calls handleListStaff makes: staff select+order, embedding select,
// and storage.createSignedUrls. signedFor lists which paths get a URL (others error).
function makeSupabase(opts: {
  staff: any[];
  embeddings: { staff_id: string }[];
  signedFor: string[];
}) {
  return {
    from(table: string) {
      if (table === 'staff') {
        return { select: () => ({ order: () => Promise.resolve({ data: opts.staff, error: null }) }) };
      }
      // staff_face_embedding
      return { select: () => Promise.resolve({ data: opts.embeddings, error: null }) };
    },
    storage: {
      from: () => ({
        createSignedUrls: (paths: string[]) =>
          Promise.resolve({
            data: paths.map(p =>
              opts.signedFor.includes(p)
                ? { path: p, signedUrl: `https://signed.example/${p}?token=abc`, error: null }
                : { path: p, signedUrl: null, error: 'not found' }
            ),
            error: null,
          }),
      }),
    },
  } as any;
}

describe('GET /staff', () => {
  it('maps photo_path → signed photo_url, null when absent, and counts embeddings', async () => {
    const supabase = makeSupabase({
      staff: [
        { id: 'a', full_name: 'Has Photo', photo_path: 'a.jpg', active: true },
        { id: 'b', full_name: 'No Photo', photo_path: null, active: true },
      ],
      embeddings: [{ staff_id: 'a' }, { staff_id: 'a' }, { staff_id: 'b' }],
      signedFor: ['a.jpg'],
    });
    const res = makeRes();

    await handleListStaff({} as any, res as any, supabase);

    expect(res.statusCode).toBe(200);
    const out = JSON.parse(res.body);
    expect(out.ok).toBe(true);

    const a = out.staff.find((s: any) => s.id === 'a');
    const b = out.staff.find((s: any) => s.id === 'b');

    expect(a.photo_url).toBe('https://signed.example/a.jpg?token=abc');
    expect(a.embedding_count).toBe(2);
    expect(a.photo_path).toBeUndefined(); // internal path not leaked to clients

    expect(b.photo_url).toBeNull();
    expect(b.embedding_count).toBe(1);
  });

  it('falls back to null photo_url when the signed-URL mint errors', async () => {
    const supabase = makeSupabase({
      staff: [{ id: 'a', full_name: 'Has Photo', photo_path: 'a.jpg', active: true }],
      embeddings: [],
      signedFor: [], // a.jpg returns an error → no URL
    });
    const res = makeRes();

    await handleListStaff({} as any, res as any, supabase);

    const out = JSON.parse(res.body);
    expect(out.staff[0].photo_url).toBeNull();
    expect(out.staff[0].embedding_count).toBe(0);
  });
});
