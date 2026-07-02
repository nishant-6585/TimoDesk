/**
 * tests/captures.test.ts — admin snapshot persistence (F7).
 *
 * Covers saveSnapshot (upload + capture insert, error propagation) and
 * listSnapshots (newest-first mapping + signed URLs, null when a URL fails).
 */

import { describe, it, expect, vi } from 'vitest';
import { saveSnapshot, listSnapshots, SNAPSHOTS_BUCKET } from '../src/captures';

describe('saveSnapshot', () => {
  it('uploads the JPEG and inserts an admin_snapshot capture row with the actor', async () => {
    const upload = vi.fn(async () => ({ error: null }));
    const insert = vi.fn(() => ({
      select: () => ({ single: async () => ({ data: { id: 'cap-1' }, error: null }) }),
    }));
    const storageFrom = vi.fn(() => ({ upload }));
    const supabase = {
      storage: { from: storageFrom },
      from: (t: string) => (t === 'capture' ? { insert } : {}),
    } as any;

    const buffer = Buffer.from('jpegbytes');
    const result = await saveSnapshot(supabase, buffer, 'admin-42', () => 1700000000000);

    expect(result).toEqual({ captureId: 'cap-1', path: 'admin/1700000000000.jpg' });
    expect(storageFrom).toHaveBeenCalledWith(SNAPSHOTS_BUCKET);
    expect(upload).toHaveBeenCalledWith('admin/1700000000000.jpg', buffer, {
      contentType: 'image/jpeg',
      upsert: false,
    });
    expect(insert).toHaveBeenCalledWith({
      kind: 'admin_snapshot',
      storage_url: 'admin/1700000000000.jpg',
      actor: 'admin-42',
    });
  });

  it('throws if the storage upload fails (and never inserts a row)', async () => {
    const insert = vi.fn();
    const supabase = {
      storage: { from: () => ({ upload: async () => ({ error: { message: 'bucket missing' } }) }) },
      from: () => ({ insert }),
    } as any;

    await expect(saveSnapshot(supabase, Buffer.from('x'), 'admin-42')).rejects.toThrow(
      /snapshot upload failed: bucket missing/
    );
    expect(insert).not.toHaveBeenCalled();
  });

  it('throws if the capture insert fails', async () => {
    const supabase = {
      storage: { from: () => ({ upload: async () => ({ error: null }) }) },
      from: () => ({
        insert: () => ({
          select: () => ({ single: async () => ({ data: null, error: { message: 'rls denied' } }) }),
        }),
      }),
    } as any;

    await expect(saveSnapshot(supabase, Buffer.from('x'), null)).rejects.toThrow(
      /capture insert failed: rls denied/
    );
  });
});

describe('listSnapshots', () => {
  function makeSupabase(rows: any[], signedFor: string[]) {
    return {
      from: () => ({
        select: () => ({
          eq: () => ({
            order: () => ({ limit: async () => ({ data: rows, error: null }) }),
          }),
        }),
      }),
      storage: {
        from: () => ({
          createSignedUrls: (paths: string[]) =>
            Promise.resolve({
              data: paths.map(p =>
                signedFor.includes(p)
                  ? { path: p, signedUrl: `https://signed.example/${p}`, error: null }
                  : { path: p, signedUrl: null, error: 'gone' }
              ),
              error: null,
            }),
        }),
      },
    } as any;
  }

  it('maps rows newest-first with signed image URLs, null when a URL fails to mint', async () => {
    const rows = [
      { id: 'a', storage_url: 'admin/2.jpg', actor: 'admin-1', taken_at: '2026-07-01T10:00:00Z' },
      { id: 'b', storage_url: 'admin/1.jpg', actor: null, taken_at: '2026-07-01T09:00:00Z' },
    ];
    const list = await listSnapshots(makeSupabase(rows, ['admin/2.jpg']));

    expect(list).toEqual([
      { id: 'a', taken_at: '2026-07-01T10:00:00Z', actor: 'admin-1', image_url: 'https://signed.example/admin/2.jpg' },
      { id: 'b', taken_at: '2026-07-01T09:00:00Z', actor: null, image_url: null },
    ]);
  });

  it('returns an empty list (and mints no URLs) when there are no captures', async () => {
    const list = await listSnapshots(makeSupabase([], []));
    expect(list).toEqual([]);
  });
});
