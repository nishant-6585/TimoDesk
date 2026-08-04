/**
 * tests/nav-points.test.ts — /nav-points CRUD + its auth gate.
 *
 * This route exists so the robot_app can drop the Supabase anon key (which forced
 * nav_points RLS wide open). Two things are worth pinning: nothing gets through
 * without a token, and a bad pose is rejected before it reaches the table — a
 * NaN coordinate saved here is a robot driving somewhere nobody chose.
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.hoisted(() => {
  process.env.DEV_AUTH_BYPASS = '0';
  process.env.KIOSK_TOKEN = 'kiosk-secret';
});

import { handleNavPoints, navPointInsert } from '../src/handlers/nav-points';

function makeReq(method: string, url: string, token?: string, body?: unknown): any {
  const chunks = body === undefined ? [] : [JSON.stringify(body)];
  return {
    method,
    url,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    on(event: string, cb: (arg?: unknown) => void) {
      if (event === 'data') chunks.forEach((c) => cb(c));
      if (event === 'end') cb();
      return this;
    },
  };
}

function makeRes() {
  const res: any = {
    statusCode: 0,
    body: '',
    writeHead: vi.fn((code: number) => {
      res.statusCode = code;
    }),
    end: vi.fn((chunk?: string) => {
      res.body = chunk ?? '';
    }),
  };
  return res;
}

const json = (res: any) => JSON.parse(res.body);

/**
 * Chainable PostgREST stub that records what it was asked to do.
 * GET /nav-points also queries `staff` (synthetic desk points), so that table
 * gets its own chain with its own result.
 */
function makeSupabase(
  result: { data?: unknown; error?: { message: string } } = {},
  staffResult: { data?: unknown; error?: { message: string } } = {}
) {
  const calls: Record<string, unknown> = {};
  const chain: any = {
    select: vi.fn(() => chain),
    order: vi.fn(() => chain),
    insert: vi.fn((row: unknown) => {
      calls.insert = row;
      return chain;
    }),
    update: vi.fn((patch: unknown) => {
      calls.update = patch;
      return chain;
    }),
    delete: vi.fn(() => {
      calls.delete = true;
      return chain;
    }),
    eq: vi.fn((_col: string, val: unknown) => {
      calls.eq = val;
      return chain;
    }),
    single: vi.fn(async () => ({ data: result.data ?? null, error: result.error ?? null })),
    then: (resolve: (v: unknown) => unknown) =>
      resolve({ data: result.data ?? [], error: result.error ?? null }),
  };
  const staffChain: any = {
    select: vi.fn(() => staffChain),
    eq: vi.fn(() => staffChain),
    not: vi.fn(() => staffChain),
    then: (resolve: (v: unknown) => unknown) =>
      resolve({ data: staffResult.data ?? [], error: staffResult.error ?? null }),
  };
  return {
    supabase: { from: vi.fn((table: string) => (table === 'staff' ? staffChain : chain)) } as any,
    calls,
    chain,
    staffChain,
  };
}

beforeEach(() => vi.clearAllMocks());

describe('auth gate', () => {
  const routes: [string, string][] = [
    ['GET', '/nav-points'],
    ['POST', '/nav-points'],
    ['PATCH', '/nav-points/abc'],
    ['DELETE', '/nav-points/abc'],
  ];

  it.each(routes)('%s %s → 401 without a token', async (method, url) => {
    const { supabase } = makeSupabase();
    const res = makeRes();
    expect(await handleNavPoints(makeReq(method, url), res, supabase)).toBe(true);
    expect(res.statusCode).toBe(401);
    expect(supabase.from).not.toHaveBeenCalled();
  });

  it('never accepts a query token (that is playback-only)', async () => {
    const { supabase } = makeSupabase();
    const res = makeRes();
    await handleNavPoints(makeReq('GET', '/nav-points?token=kiosk-secret'), res, supabase);
    expect(res.statusCode).toBe(401);
  });

  it('leaves unrelated routes alone', async () => {
    const { supabase } = makeSupabase();
    const res = makeRes();
    expect(await handleNavPoints(makeReq('GET', '/staff'), res, supabase)).toBe(false);
    expect(res.writeHead).not.toHaveBeenCalled();
  });
});

describe('GET /nav-points', () => {
  it('returns the points ordered by sort_order then created_at', async () => {
    const rows = [{ id: 'p1', name: 'Reception' }];
    const { supabase, chain } = makeSupabase({ data: rows });
    const res = makeRes();
    await handleNavPoints(makeReq('GET', '/nav-points', 'kiosk-secret'), res, supabase);
    expect(res.statusCode).toBe(200);
    expect(json(res)).toEqual({ ok: true, points: rows });
    expect(chain.order).toHaveBeenCalledWith('sort_order', { ascending: true });
    expect(chain.order).toHaveBeenCalledWith('created_at', { ascending: true });
  });

  it('appends enrolled staff desks as synthetic points after the real ones', async () => {
    const rows = [{ id: 'p1', name: 'Reception' }];
    const staff = [
      { id: 's1', full_name: 'David', desk_x: 1.5, desk_y: -2, desk_z: 0, desk_rotation: 90 },
    ];
    const { supabase } = makeSupabase({ data: rows }, { data: staff });
    const res = makeRes();
    await handleNavPoints(makeReq('GET', '/nav-points', 'kiosk-secret'), res, supabase);
    expect(res.statusCode).toBe(200);
    expect(json(res).points).toEqual([
      rows[0],
      expect.objectContaining({ id: 'staff-desk:s1', name: 'David', kind: 'staff_desk' }),
    ]);
  });

  it('still serves the real points when the staff-desk query fails', async () => {
    const rows = [{ id: 'p1', name: 'Reception' }];
    const { supabase } = makeSupabase({ data: rows }, { error: { message: 'staff down' } });
    const res = makeRes();
    await handleNavPoints(makeReq('GET', '/nav-points', 'kiosk-secret'), res, supabase);
    expect(res.statusCode).toBe(200);
    expect(json(res)).toEqual({ ok: true, points: rows });
  });

  it('surfaces a database error as a 500', async () => {
    const { supabase } = makeSupabase({ error: { message: 'rls denied' } });
    const res = makeRes();
    await handleNavPoints(makeReq('GET', '/nav-points', 'kiosk-secret'), res, supabase);
    expect(res.statusCode).toBe(500);
    expect(json(res).reason).toBe('rls denied');
  });
});

describe('POST /nav-points', () => {
  it('inserts a validated row and echoes the created point', async () => {
    const { supabase, calls } = makeSupabase({ data: { id: 'p9', name: 'Lab' } });
    const res = makeRes();
    await handleNavPoints(
      makeReq('POST', '/nav-points', 'kiosk-secret', {
        name: '  Lab  ',
        x: 1.5,
        y: -2,
        rotation: 90,
        kind: 'welcome',
      }),
      res,
      supabase
    );
    expect(res.statusCode).toBe(201);
    expect(calls.insert).toMatchObject({
      name: 'Lab',
      x: 1.5,
      y: -2,
      z: 0,
      rotation: 90,
      kind: 'welcome',
      description: null,
    });
  });

  it('rejects a non-finite coordinate before it reaches the table', async () => {
    const { supabase, chain } = makeSupabase();
    const res = makeRes();
    await handleNavPoints(
      makeReq('POST', '/nav-points', 'kiosk-secret', { name: 'Bad', x: null, y: 2 }),
      res,
      supabase
    );
    expect(res.statusCode).toBe(400);
    expect(chain.insert).not.toHaveBeenCalled();
  });

  it('rejects malformed JSON', async () => {
    const { supabase } = makeSupabase();
    const res = makeRes();
    const req = makeReq('POST', '/nav-points', 'kiosk-secret');
    req.on = function (event: string, cb: (arg?: unknown) => void) {
      if (event === 'data') cb('{not json');
      if (event === 'end') cb();
      return this;
    };
    await handleNavPoints(req, res, supabase);
    expect(res.statusCode).toBe(400);
  });
});

describe('PATCH /nav-points/:id', () => {
  it('updates name + description and never the coordinates', async () => {
    const { supabase, calls } = makeSupabase();
    const res = makeRes();
    await handleNavPoints(
      makeReq('PATCH', '/nav-points/p1', 'kiosk-secret', {
        name: 'Front Desk',
        description: 'We have arrived',
        x: 999, // must be ignored — re-capture is the only way to move a point
      }),
      res,
      supabase
    );
    expect(res.statusCode).toBe(200);
    expect(calls.update).toEqual({ name: 'Front Desk', description: 'We have arrived' });
    expect(calls.eq).toBe('p1');
  });

  it('clears the arrival text when description is sent empty', async () => {
    const { supabase, calls } = makeSupabase();
    const res = makeRes();
    await handleNavPoints(
      makeReq('PATCH', '/nav-points/p1', 'kiosk-secret', { description: '' }),
      res,
      supabase
    );
    expect(calls.update).toEqual({ description: null });
  });

  it('400s when there is nothing to update', async () => {
    const { supabase, chain } = makeSupabase();
    const res = makeRes();
    await handleNavPoints(makeReq('PATCH', '/nav-points/p1', 'kiosk-secret', {}), res, supabase);
    expect(res.statusCode).toBe(400);
    expect(chain.update).not.toHaveBeenCalled();
  });
});

describe('DELETE /nav-points/:id', () => {
  it('deletes by id', async () => {
    const { supabase, calls } = makeSupabase();
    const res = makeRes();
    await handleNavPoints(makeReq('DELETE', '/nav-points/p1', 'kiosk-secret'), res, supabase);
    expect(res.statusCode).toBe(200);
    expect(calls.delete).toBe(true);
    expect(calls.eq).toBe('p1');
  });
});

describe('navPointInsert', () => {
  it('requires a name', () => {
    expect(navPointInsert({ x: 1, y: 2 })).toEqual({ ok: false, reason: 'name is required' });
    expect(navPointInsert({ name: '   ', x: 1, y: 2 }).ok).toBe(false);
  });

  it('requires finite x and y', () => {
    expect(navPointInsert({ name: 'a', x: NaN, y: 2 }).ok).toBe(false);
    expect(navPointInsert({ name: 'a', x: Infinity, y: 2 }).ok).toBe(false);
    expect(navPointInsert({ name: 'a', x: '1', y: 2 }).ok).toBe(false); // strings are not poses
    expect(navPointInsert({ name: 'a', x: 0, y: 0 }).ok).toBe(true); // origin is valid
  });

  it('rejects an unknown kind', () => {
    expect(navPointInsert({ name: 'a', x: 1, y: 2, kind: 'teleport' }).ok).toBe(false);
  });

  it('defaults z, rotation and kind', () => {
    const r = navPointInsert({ name: 'a', x: 1, y: 2 });
    expect(r.ok && r.row).toMatchObject({ z: 0, rotation: 0, kind: 'navigation' });
  });
});
