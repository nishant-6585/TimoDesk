/**
 * tests/entra.test.ts — Microsoft Entra ID → staff directory sync.
 *
 * All Graph HTTP goes through the injected fetchImpl; Supabase is a chainable
 * mock capturing inserts/updates. Covers: create, adopt-by-name, update with
 * operator notify_channel preserved, deactivate-departed, pagination, and the
 * unconfigured guard.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { syncEntraStaff, entraConfigured, GraphUser } from '../src/services/entra';

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

  it('deactivates synced staff missing from Graph, leaves manual rows alone', async () => {
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
    expect(updates).toEqual([{ id: 's1', patch: { active: false } }]);
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
