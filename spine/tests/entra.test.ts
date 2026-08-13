/**
 * tests/entra.test.ts — Microsoft Entra ID → staff directory sync.
 *
 * All Graph HTTP goes through the injected fetchImpl; Supabase is a chainable
 * mock capturing inserts/updates. Covers: create, adopt-by-name, update with
 * operator notify_channel preserved, deactivate-departed, pagination, and the
 * unconfigured guard.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  syncEntraStaff,
  entraConfigured,
  GraphUser,
  fetchDeltaChanges,
  fetchGroupMemberIds,
  purgeOffboardedEmbeddings,
  runEntraSync,
} from '../src/services/entra';

const ENV_KEYS = ['ENTRA_TENANT_ID', 'ENTRA_CLIENT_ID', 'ENTRA_CLIENT_SECRET'] as const;
const savedEnv: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const k of ENV_KEYS) savedEnv[k] = process.env[k];
  process.env.ENTRA_TENANT_ID = 'tenant-1';
  process.env.ENTRA_CLIENT_ID = 'client-1';
  process.env.ENTRA_CLIENT_SECRET = 'secret-1';
});
afterEach(() => {
  for (const k of ENV_KEYS) {
    if (savedEnv[k] === undefined) delete process.env[k];
    else process.env[k] = savedEnv[k];
  }
});

/** Response-shaped stub. */
const ok = (payload: unknown) => ({
  ok: true,
  json: async () => payload,
  text: async () => JSON.stringify(payload),
});

/** fetchImpl serving the token endpoint + one or more /users pages. */
function makeFetch(pages: Array<{ value: GraphUser[]; '@odata.nextLink'?: string }>) {
  let page = 0;
  return vi.fn(async (url: string) => {
    if (url.includes('login.microsoftonline.com')) return ok({ access_token: 'tok' });
    if (url.includes('graph.microsoft.com')) return ok(pages[page++]);
    throw new Error(`unexpected fetch: ${url}`);
  }) as unknown as typeof fetch;
}

/** Chainable staff-table mock; select resolves rows, insert/update are captured. */
function makeSupabase(staffRows: any[]) {
  const inserts: any[] = [];
  const updates: Array<{ id: string; patch: any }> = [];
  const client: any = {
    from(table: string) {
      if (table !== 'staff') throw new Error(`unexpected table ${table}`);
      return {
        select: () => Promise.resolve({ data: staffRows, error: null }),
        insert: (row: any) => {
          inserts.push(row);
          return Promise.resolve({ error: null });
        },
        update: (patch: any) => ({
          eq: (_col: string, id: string) => {
            updates.push({ id, patch });
            return Promise.resolve({ error: null });
          },
        }),
      };
    },
  };
  return { client, inserts, updates };
}

const user = (over: Partial<GraphUser>): GraphUser => ({
  id: 'g1',
  displayName: 'Alice Kumar',
  jobTitle: 'Sales Lead',
  mail: 'alice@xboom.in',
  mobilePhone: '+919800000001',
  accountEnabled: true,
  ...over,
});

describe('entraConfigured', () => {
  it('is true with all three env vars, false when any is missing', () => {
    expect(entraConfigured()).toBe(true);
    delete process.env.ENTRA_CLIENT_SECRET;
    expect(entraConfigured()).toBe(false);
  });
});

describe('syncEntraStaff', () => {
  it('throws a clear error when unconfigured', async () => {
    delete process.env.ENTRA_TENANT_ID;
    const { client } = makeSupabase([]);
    await expect(syncEntraStaff(client)).rejects.toThrow(/Entra not configured/);
  });

  it('creates staff for new Graph users (Employee, email notify_channel)', async () => {
    const { client, inserts } = makeSupabase([]);
    const summary = await syncEntraStaff(client, { fetchImpl: makeFetch([{ value: [user({})] }]) });
    expect(summary).toMatchObject({ fetched: 1, created: 1, updated: 0, adopted: 0, deactivated: 0 });
    expect(inserts[0]).toMatchObject({
      full_name: 'Alice Kumar',
      role: 'Sales Lead',
      phone: '+919800000001',
      notify_channel: 'email:alice@xboom.in',
      active: true,
      entra_id: 'g1',
      person_type: 'Employee',
    });
  });

  it('adopts an existing manual row by name instead of duplicating', async () => {
    const manual = {
      id: 's1', full_name: 'Alice Kumar', role: null, phone: null,
      notify_channel: null, active: true, entra_id: null,
    };
    const { client, inserts, updates } = makeSupabase([manual]);
    const summary = await syncEntraStaff(client, { fetchImpl: makeFetch([{ value: [user({})] }]) });
    expect(summary).toMatchObject({ created: 0, adopted: 1 });
    expect(inserts).toHaveLength(0);
    expect(updates[0]).toMatchObject({ id: 's1', patch: { entra_id: 'g1', role: 'Sales Lead' } });
  });

  it('updates changed fields but never clobbers an operator-set notify_channel', async () => {
    const synced = {
      id: 's1', full_name: 'Alice Kumar', role: 'Sales Lead', phone: '+919800000001',
      notify_channel: 'slack:U0ALICE', active: true, entra_id: 'g1',
    };
    const { client, updates } = makeSupabase([synced]);
    const summary = await syncEntraStaff(client, {
      fetchImpl: makeFetch([{ value: [user({ jobTitle: 'Head of Sales' })] }]),
    });
    expect(summary).toMatchObject({ updated: 1 });
    expect(updates[0].patch).toMatchObject({
      role: 'Head of Sales',
      notify_channel: 'slack:U0ALICE', // preserved
    });
  });

  it('is a no-op (no update call) when nothing changed', async () => {
    const synced = {
      id: 's1', full_name: 'Alice Kumar', role: 'Sales Lead', phone: '+919800000001',
      notify_channel: 'email:alice@xboom.in', active: true, entra_id: 'g1',
    };
    const { client, updates, inserts } = makeSupabase([synced]);
    const summary = await syncEntraStaff(client, { fetchImpl: makeFetch([{ value: [user({})] }]) });
    expect(summary).toMatchObject({ created: 0, updated: 0, adopted: 0, deactivated: 0 });
    expect(updates).toHaveLength(0);
    expect(inserts).toHaveLength(0);
  });

  it('deactivates synced staff missing from Graph (offboard clock set), leaves manual rows alone', async () => {
    const departed = {
      id: 's1', full_name: 'Bob Gone', role: null, phone: null,
      notify_channel: null, active: true, entra_id: 'g-old',
    };
    const manual = {
      id: 's2', full_name: 'Vishal', role: 'Founder', phone: null,
      notify_channel: null, active: true, entra_id: null,
    };
    const { client, updates } = makeSupabase([departed, manual]);
    const summary = await syncEntraStaff(client, { fetchImpl: makeFetch([{ value: [] }]) });
    expect(summary).toMatchObject({ deactivated: 1 });
    expect(updates).toHaveLength(1);
    expect(updates[0].id).toBe('s1');
    expect(updates[0].patch).toMatchObject({ active: false });
    expect(updates[0].patch.entra_deactivated_at).toBeTruthy(); // offboard purge clock
  });

  it('clears the offboard clock when a disabled account is re-enabled', async () => {
    const disabled = {
      id: 's1', full_name: 'Alice Kumar', role: 'Sales Lead', phone: '+919800000001',
      notify_channel: 'email:alice@xboom.in', active: false, entra_id: 'g1',
      entra_deactivated_at: '2026-08-01T00:00:00Z',
    };
    const { client, updates } = makeSupabase([disabled]);
    await syncEntraStaff(client, { fetchImpl: makeFetch([{ value: [user({})] }]) });
    expect(updates[0].patch).toMatchObject({ active: true, entra_deactivated_at: null });
  });

  it('follows @odata.nextLink pagination', async () => {
    const { client, inserts } = makeSupabase([]);
    const fetchImpl = makeFetch([
      { value: [user({ id: 'g1', displayName: 'A One', mail: 'a@x.in' })], '@odata.nextLink': 'https://graph.microsoft.com/v1.0/users?page=2' },
      { value: [user({ id: 'g2', displayName: 'B Two', mail: 'b@x.in' })] },
    ]);
    const summary = await syncEntraStaff(client, { fetchImpl });
    expect(summary).toMatchObject({ fetched: 2, created: 2 });
    expect(inserts.map(i => i.entra_id).sort()).toEqual(['g1', 'g2']);
  });
});

describe('fetchDeltaChanges', () => {
  const respond = (map: Record<string, unknown>, statuses: Record<string, number> = {}) =>
    (async (url: string) => {
      if (statuses[url]) return { ok: false, status: statuses[url], json: async () => ({}), text: async () => '' };
      const payload = map[url];
      if (payload === undefined) throw new Error(`unexpected fetch: ${url}`);
      return ok(payload);
    }) as unknown as typeof fetch;

  it('splits changed vs @removed ids and returns the new deltaLink', async () => {
    const fetchImpl = respond({
      'dl-old': {
        value: [{ id: 'g1' }, { id: 'g2', '@removed': { reason: 'deleted' } }],
        '@odata.nextLink': 'dl-old-p2',
      },
      'dl-old-p2': { value: [{ id: 'g3' }], '@odata.deltaLink': 'dl-new' },
    });
    const r = await fetchDeltaChanges('tok', 'dl-old', { fetchImpl });
    expect(r).toEqual({ changedIds: ['g1', 'g3'], removedIds: ['g2'], deltaLink: 'dl-new' });
  });

  it("returns 'resync' on 410 Gone (expired delta token)", async () => {
    const fetchImpl = respond({}, { 'dl-old': 410 });
    expect(await fetchDeltaChanges('tok', 'dl-old', { fetchImpl })).toBe('resync');
  });
});

describe('fetchGroupMemberIds', () => {
  it('collects user ids across pages', async () => {
    const fetchImpl = (async (url: string) => {
      if (url.includes('/groups/grp-1/transitiveMembers/microsoft.graph.user')) {
        return ok({ value: [{ id: 'g1' }, { id: 'g2' }], '@odata.nextLink': 'members-p2' });
      }
      if (url === 'members-p2') return ok({ value: [{ id: 'g3' }] });
      throw new Error(`unexpected fetch: ${url}`);
    }) as unknown as typeof fetch;
    const ids = await fetchGroupMemberIds('tok', 'grp-1', { fetchImpl });
    expect([...ids].sort()).toEqual(['g1', 'g2', 'g3']);
  });

  it('throws on a Graph error (consent stays fail-closed upstream)', async () => {
    const fetchImpl = (async () => ({ ok: false, status: 403, text: async () => 'denied' })) as unknown as typeof fetch;
    await expect(fetchGroupMemberIds('tok', 'grp-1', { fetchImpl })).rejects.toThrow(/403/);
  });
});

describe('purgeOffboardedEmbeddings', () => {
  function makePurgeDb(staffRows: any[], entraEmbeddingCounts: Record<string, number>) {
    const deletes: string[] = [];
    const updates: Array<{ id: string; patch: any }> = [];
    const client: any = {
      from(table: string) {
        if (table === 'staff') {
          return {
            select: () => Promise.resolve({ data: staffRows, error: null }),
            update: (patch: any) => ({
              eq: (_c: string, id: string) => {
                updates.push({ id, patch });
                return Promise.resolve({ error: null });
              },
            }),
          };
        }
        if (table === 'staff_face_embedding') {
          return {
            select: (_cols: string, _opts: any) => ({
              eq: (_c: string, id: string) => ({
                like: () => Promise.resolve({ count: entraEmbeddingCounts[id] ?? 0 }),
              }),
            }),
            delete: () => ({
              eq: (_c: string, id: string) => ({
                like: () => {
                  deletes.push(id);
                  return Promise.resolve({ error: null });
                },
              }),
            }),
          };
        }
        throw new Error(`unexpected table ${table}`);
      },
    };
    return { client, deletes, updates };
  }

  const daysAgo = (n: number) => new Date(Date.now() - n * 24 * 3600 * 1000).toISOString();

  it('purges entra-photo embeddings of staff deactivated past the window, audit-logged', async () => {
    const rows = [
      { id: 's1', full_name: 'Gone Long Ago', active: false, entra_id: 'g1', entra_deactivated_at: daysAgo(45) },
      { id: 's2', full_name: 'Recently Gone', active: false, entra_id: 'g2', entra_deactivated_at: daysAgo(5) },
      { id: 's3', full_name: 'Manual Inactive', active: false, entra_id: null, entra_deactivated_at: null },
      { id: 's4', full_name: 'Still Here', active: true, entra_id: 'g4', entra_deactivated_at: null },
    ];
    const { client, deletes, updates } = makePurgeDb(rows, { s1: 2 });
    const events: any[] = [];
    const logStub = (async (type: string, payload?: any) => { events.push({ type, payload }); }) as any;

    const summary = await purgeOffboardedEmbeddings(client, 30, logStub);
    expect(summary).toEqual({ staff_purged: 1, embeddings_deleted: 2 });
    expect(deletes).toEqual(['s1']);
    expect(updates[0]).toMatchObject({ id: 's1', patch: { entra_photo_status: 'purged', entra_photo_etag: null } });
    expect(events[0]).toMatchObject({ type: 'entra_offboard_purge', payload: { staff_id: 's1', embeddings_deleted: 2 } });
  });

  it('is a no-op for already-purged staff (zero entra-photo embeddings)', async () => {
    const rows = [
      { id: 's1', full_name: 'Gone Long Ago', active: false, entra_id: 'g1', entra_deactivated_at: daysAgo(45) },
    ];
    const { client, deletes } = makePurgeDb(rows, { s1: 0 });
    const summary = await purgeOffboardedEmbeddings(client, 30, (async () => {}) as any);
    expect(summary).toEqual({ staff_purged: 0, embeddings_deleted: 0 });
    expect(deletes).toHaveLength(0);
  });
});

describe('runEntraSync', () => {
  const EXTRA_ENV = ['ENTRA_CONSENT_GROUP_ID', 'ENTRA_PHOTO_CONSENT_MODE', 'ENTRA_OFFBOARD_PURGE_DAYS'] as const;
  const savedExtra: Record<string, string | undefined> = {};
  beforeEach(() => {
    for (const k of EXTRA_ENV) {
      savedExtra[k] = process.env[k];
      delete process.env[k];
    }
  });
  afterEach(() => {
    for (const k of EXTRA_ENV) {
      if (savedExtra[k] === undefined) delete process.env[k];
      else process.env[k] = savedExtra[k];
    }
  });

  /** Multi-table mock: staff + entra_sync_state (+ empty embeddings for the purge pass). */
  function makeRunDb(staffRows: any[], deltaState: string | null) {
    const inserts: any[] = [];
    const updates: Array<{ id: string; patch: any }> = [];
    const stateUpserts: any[] = [];
    const client: any = {
      from(table: string) {
        if (table === 'staff') {
          return {
            select: () => Promise.resolve({ data: staffRows, error: null }),
            insert: (row: any) => { inserts.push(row); return Promise.resolve({ error: null }); },
            update: (patch: any) => ({
              eq: (_c: string, id: string) => { updates.push({ id, patch }); return Promise.resolve({ error: null }); },
            }),
          };
        }
        if (table === 'entra_sync_state') {
          return {
            select: () => ({
              eq: () => ({
                maybeSingle: () => Promise.resolve({ data: deltaState ? { value: deltaState } : null, error: null }),
              }),
            }),
            upsert: (row: any) => { stateUpserts.push(row); return Promise.resolve({ error: null }); },
          };
        }
        if (table === 'staff_face_embedding') {
          return {
            select: (_cols: string, opts?: any) =>
              opts?.count
                ? { eq: () => ({ like: () => Promise.resolve({ count: 0 }) }) }
                : Promise.resolve({ data: [], error: null }),
          };
        }
        throw new Error(`unexpected table ${table}`);
      },
    };
    return { client, inserts, updates, stateUpserts };
  }

  it('full mode: enumerates users, mints a deltaLink, skips photos without a consent group', async () => {
    const { client, inserts, stateUpserts } = makeRunDb([], null);
    const fetchImpl = (async (url: string) => {
      if (url.includes('login.microsoftonline.com')) return ok({ access_token: 'tok' });
      if (url.includes('$deltaToken=latest')) return ok({ '@odata.deltaLink': 'dl-1' });
      if (url.includes('/users?$select')) return ok({ value: [user({})] });
      throw new Error(`unexpected fetch: ${url}`);
    }) as unknown as typeof fetch;

    const summary = await runEntraSync(client, { fetchImpl, logEventImpl: (async () => {}) as any });
    expect(summary).toMatchObject({ mode: 'full', fetched: 1, created: 1, removed: 0, photos: null });
    expect(summary.photos_skipped_reason).toMatch(/ENTRA_CONSENT_GROUP_ID/);
    expect(inserts).toHaveLength(1);
    expect(stateUpserts[0]).toMatchObject({ key: 'users_delta', value: 'dl-1' });
  });

  it('delta mode: re-fetches changed users in full, deactivates @removed, stores the new deltaLink', async () => {
    const staffRows = [
      { id: 's1', full_name: 'Alice Kumar', role: 'Sales Lead', phone: '+919800000001',
        notify_channel: 'email:alice@xboom.in', active: true, entra_id: 'g1' },
      { id: 's2', full_name: 'Bob Gone', role: null, phone: null,
        notify_channel: null, active: true, entra_id: 'g2' },
    ];
    const { client, updates, stateUpserts } = makeRunDb(staffRows, 'dl-old');
    const fetchImpl = (async (url: string) => {
      if (url.includes('login.microsoftonline.com')) return ok({ access_token: 'tok' });
      if (url === 'dl-old') {
        return ok({
          value: [{ id: 'g1' }, { id: 'g2', '@removed': { reason: 'deleted' } }],
          '@odata.deltaLink': 'dl-new',
        });
      }
      if (url.includes('/users/g1?$select')) return ok(user({ jobTitle: 'Head of Sales' }));
      throw new Error(`unexpected fetch: ${url}`);
    }) as unknown as typeof fetch;

    const summary = await runEntraSync(client, { fetchImpl, logEventImpl: (async () => {}) as any });
    expect(summary).toMatchObject({ mode: 'delta', updated: 1, deactivated: 1, removed: 1 });
    expect(updates.find(u => u.id === 's1')?.patch).toMatchObject({ role: 'Head of Sales' });
    expect(updates.find(u => u.id === 's2')?.patch).toMatchObject({ active: false });
    expect(stateUpserts[0]).toMatchObject({ key: 'users_delta', value: 'dl-new' });
  });
});
