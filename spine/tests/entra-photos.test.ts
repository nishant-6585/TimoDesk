/**
 * tests/entra-photos.test.ts — Entra directory photo → face-embedding import.
 *
 * Graph HTTP goes through the injected fetchImpl and the embedder is stubbed
 * (no face-api/canvas natives in the container). Covers: happy path (insert +
 * thumbnail + status), etag skip, no-photo, multi-face and small-face rejects,
 * the collision gate, consent revocation, and photo-change replacement.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { syncEntraPhotos, EmbedResultLike } from '../src/services/entra-photos';
import { FACE_CONFIG } from '../src/config/face-recognition';

const ENV_KEYS = ['ENTRA_MIN_FACE_PX'] as const;
const savedEnv: Record<string, string | undefined> = {};
beforeEach(() => {
  for (const k of ENV_KEYS) {
    savedEnv[k] = process.env[k];
    delete process.env[k];
  }
});
afterEach(() => {
  for (const k of ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
});

/** 128-d vector with every component = v. */
const vec = (v: number) => Array(FACE_CONFIG.embedding_dim).fill(v);

const okJson = (payload: unknown) => ({
  ok: true,
  status: 200,
  json: async () => payload,
  text: async () => JSON.stringify(payload),
});
const notFound = { ok: false, status: 404, json: async () => ({}), text: async () => 'not found' };
const okBytes = (bytes: number[]) => ({
  ok: true,
  status: 200,
  arrayBuffer: async () => new Uint8Array(bytes).buffer,
});

/** fetchImpl serving photo meta + binary per Graph user id. */
function makePhotoFetch(photos: Record<string, { etag: string | null; bytes: number[] } | null>) {
  const calls: string[] = [];
  const f = (async (url: string) => {
    calls.push(url);
    const m = url.match(/\/users\/([^/]+)\/photo(\/\$value)?$/);
    if (!m) throw new Error(`unexpected fetch: ${url}`);
    const photo = photos[m[1]];
    if (!photo) return notFound;
    if (m[2]) return okBytes(photo.bytes);
    return okJson({ '@odata.mediaEtag': photo.etag ?? undefined });
  }) as unknown as typeof fetch;
  return { f, calls };
}

interface DbState {
  staff: any[];
  embeddings: any[];
}

/** Chainable mock over staff / staff_face_embedding / storage. */
function makeDb(state: DbState) {
  const staffUpdates: Array<{ id: string; patch: any }> = [];
  const embInserts: any[] = [];
  const embDeletes: string[] = [];
  const uploads: string[] = [];
  const client: any = {
    from(table: string) {
      if (table === 'staff') {
        return {
          select: () => Promise.resolve({ data: state.staff, error: null }),
          update: (patch: any) => ({
            eq: (_c: string, id: string) => {
              staffUpdates.push({ id, patch });
              return Promise.resolve({ error: null });
            },
          }),
        };
      }
      if (table === 'staff_face_embedding') {
        return {
          select: () => Promise.resolve({ data: state.embeddings, error: null }),
          insert: (row: any) => {
            embInserts.push(row);
            return Promise.resolve({ error: null });
          },
          delete: () => ({
            eq: (_c: string, id: string) => ({
              like: () => {
                embDeletes.push(id);
                return Promise.resolve({ error: null });
              },
            }),
          }),
        };
      }
      throw new Error(`unexpected table ${table}`);
    },
    storage: {
      from: (_bucket: string) => ({
        upload: (path: string) => {
          uploads.push(path);
          return Promise.resolve({ error: null });
        },
      }),
    },
  };
  return { client, staffUpdates, embInserts, embDeletes, uploads };
}

const staffRow = (over: Partial<any> = {}) => ({
  id: 's1',
  full_name: 'Alice Kumar',
  active: true,
  entra_id: 'g1',
  photo_path: null,
  entra_photo_etag: null,
  entra_photo_status: null,
  ...over,
});

const goodEmbed = (over: Partial<EmbedResultLike> = {}): EmbedResultLike => ({
  ok: true,
  embedding: vec(1),
  thumbnail: Buffer.from('jpeg'),
  faceBox: { x: 0, y: 0, width: 300, height: 300 },
  ...over,
});

const noopLog = (async () => {}) as any;

describe('syncEntraPhotos', () => {
  it('embeds a consented photo: entra-photo consent_ref, thumbnail fill, status ok', async () => {
    const { client, staffUpdates, embInserts, uploads } = makeDb({ staff: [staffRow()], embeddings: [] });
    const { f } = makePhotoFetch({ g1: { etag: 'W/"e1"', bytes: [1, 2, 3] } });
    const events: any[] = [];

    const summary = await syncEntraPhotos(client, 'tok', new Set(['g1']), {
      fetchImpl: f,
      embedImpl: async () => goodEmbed(),
      logEventImpl: (async (type: string, payload?: any) => { events.push({ type, payload }); }) as any,
    });

    expect(summary).toMatchObject({ considered: 1, embedded: 1, errors: 0, collisions: 0 });
    expect(embInserts[0]).toMatchObject({ staff_id: 's1', consent_ref: 'entra-photo:W/"e1"' });
    expect(embInserts[0].consent_at).toBeTruthy();
    expect(uploads).toEqual(['s1.jpg']); // photo_path was null → thumbnail filled
    const statusPatch = staffUpdates.find(u => u.patch.entra_photo_status);
    expect(statusPatch?.patch).toMatchObject({ entra_photo_status: 'ok', entra_photo_etag: 'W/"e1"' });
    expect(events.map(e => e.type)).toContain('entra_photo_embedded');
  });

  it('skips an unchanged photo (etag match) without downloading the binary', async () => {
    const row = staffRow({ entra_photo_etag: 'W/"e1"', entra_photo_status: 'ok' });
    const { client, embInserts } = makeDb({ staff: [row], embeddings: [] });
    const { f, calls } = makePhotoFetch({ g1: { etag: 'W/"e1"', bytes: [1] } });

    const summary = await syncEntraPhotos(client, 'tok', new Set(['g1']), {
      fetchImpl: f,
      embedImpl: async () => { throw new Error('must not embed'); },
      logEventImpl: noopLog,
    });

    expect(summary).toMatchObject({ skipped_unchanged: 1, embedded: 0 });
    expect(embInserts).toHaveLength(0);
    expect(calls.some(u => u.endsWith('/$value'))).toBe(false); // meta only
  });

  it("marks 'none' when the user has no photo", async () => {
    const { client, staffUpdates } = makeDb({ staff: [staffRow()], embeddings: [] });
    const { f } = makePhotoFetch({ g1: null });
    const summary = await syncEntraPhotos(client, 'tok', new Set(['g1']), {
      fetchImpl: f,
      embedImpl: async () => goodEmbed(),
      logEventImpl: noopLog,
    });
    expect(summary).toMatchObject({ no_photo: 1, embedded: 0 });
    expect(staffUpdates[0].patch).toMatchObject({ entra_photo_status: 'none' });
  });

  it('rejects group shots (multiple faces) and tiny faces', async () => {
    const rows = [staffRow(), staffRow({ id: 's2', full_name: 'Bob Small', entra_id: 'g2' })];
    const { client, staffUpdates, embInserts } = makeDb({ staff: rows, embeddings: [] });
    const { f } = makePhotoFetch({
      g1: { etag: 'e-multi', bytes: [1] },
      g2: { etag: 'e-tiny', bytes: [2] },
    });
    const embeds: Record<string, EmbedResultLike> = {
      'e-multi': { ok: false, facesFound: 3, error: 'Multiple faces detected' },
      'e-tiny': goodEmbed({ faceBox: { x: 0, y: 0, width: 60, height: 60 } }), // < 120 px default
    };
    let call = 0;
    const summary = await syncEntraPhotos(client, 'tok', new Set(['g1', 'g2']), {
      fetchImpl: f,
      embedImpl: async () => (call++ === 0 ? embeds['e-multi'] : embeds['e-tiny']),
      logEventImpl: noopLog,
    });
    expect(summary).toMatchObject({ rejected_multi_face: 1, rejected_quality: 1, embedded: 0 });
    expect(embInserts).toHaveLength(0);
    expect(staffUpdates.find(u => u.id === 's1')?.patch).toMatchObject({ entra_photo_status: 'rejected_multi_face' });
    expect(staffUpdates.find(u => u.id === 's2')?.patch).toMatchObject({ entra_photo_status: 'rejected_quality' });
  });

  it('rejects an embedding that collides with a different person', async () => {
    const { client, staffUpdates, embInserts } = makeDb({
      staff: [staffRow()],
      // Another person's embedding sits at vec(1); the new photo embeds to
      // vec(1.01) → L2 ≈ 0.113, well inside threshold+margin → collision.
      embeddings: [{ staff_id: 's-other', embedding: vec(1), consent_ref: 'robot-pose-0' }],
    });
    const { f } = makePhotoFetch({ g1: { etag: 'e1', bytes: [1] } });
    const summary = await syncEntraPhotos(client, 'tok', new Set(['g1']), {
      fetchImpl: f,
      embedImpl: async () => goodEmbed({ embedding: vec(1.01) }),
      logEventImpl: noopLog,
    });
    expect(summary).toMatchObject({ collisions: 1, embedded: 0 });
    expect(embInserts).toHaveLength(0);
    expect(staffUpdates[0].patch).toMatchObject({ entra_photo_status: 'collision' });
  });

  it('deletes imported embeddings when consent is withdrawn (group removal), audit-logged', async () => {
    const row = staffRow({ entra_photo_etag: 'W/"e1"', entra_photo_status: 'ok' });
    const { client, staffUpdates, embDeletes } = makeDb({
      staff: [row],
      embeddings: [{ staff_id: 's1', embedding: vec(1), consent_ref: 'entra-photo:W/"e1"' }],
    });
    const { f, calls } = makePhotoFetch({});
    const events: any[] = [];
    const summary = await syncEntraPhotos(client, 'tok', new Set([]), {
      fetchImpl: f,
      embedImpl: async () => goodEmbed(),
      logEventImpl: (async (type: string, payload?: any) => { events.push({ type, payload }); }) as any,
    });
    expect(summary).toMatchObject({ no_consent: 1, revoked: 1 });
    expect(embDeletes).toEqual(['s1']);
    expect(calls).toHaveLength(0); // no Graph photo call for a non-consented user
    expect(staffUpdates[0].patch).toMatchObject({ entra_photo_status: 'no_consent', entra_photo_etag: null });
    expect(events[0]).toMatchObject({ type: 'entra_consent_revoked', payload: { staff_id: 's1' } });
  });

  it('replaces the previous entra-photo embedding when the photo changes; on-robot poses untouched', async () => {
    const row = staffRow({ entra_photo_etag: 'W/"old"', entra_photo_status: 'ok', photo_path: 's1.jpg' });
    const { client, embDeletes, embInserts, uploads } = makeDb({
      staff: [row],
      embeddings: [
        { staff_id: 's1', embedding: vec(1), consent_ref: 'entra-photo:W/"old"' },
        { staff_id: 's1', embedding: vec(1.005), consent_ref: 'alice-pose-0' },
      ],
    });
    const { f } = makePhotoFetch({ g1: { etag: 'W/"new"', bytes: [9] } });
    const summary = await syncEntraPhotos(client, 'tok', new Set(['g1']), {
      fetchImpl: f,
      // New photo embeds close to Alice's OWN existing embeddings — the
      // collision gate only fires for OTHER people.
      embedImpl: async () => goodEmbed({ embedding: vec(1.01) }),
      logEventImpl: noopLog,
    });
    expect(summary).toMatchObject({ embedded: 1, collisions: 0 });
    expect(embDeletes).toEqual(['s1']); // delete is scoped to entra-photo:% by the query
    expect(embInserts[0]).toMatchObject({ consent_ref: 'entra-photo:W/"new"' });
    expect(uploads).toHaveLength(0); // photo_path already set → never clobbered
  });

  it('mode all (null consent set): every active synced staff is processed', async () => {
    const { client, embInserts } = makeDb({ staff: [staffRow()], embeddings: [] });
    const { f } = makePhotoFetch({ g1: { etag: 'e1', bytes: [1] } });
    const summary = await syncEntraPhotos(client, 'tok', null, {
      fetchImpl: f,
      embedImpl: async () => goodEmbed(),
      logEventImpl: noopLog,
    });
    expect(summary).toMatchObject({ embedded: 1, no_consent: 0 });
    expect(embInserts).toHaveLength(1);
  });
});
