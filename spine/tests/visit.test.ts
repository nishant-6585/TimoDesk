/**
 * tests/visit.test.ts — POST /visit (visitor check-in → host notification, #70)
 *
 * Covers: happy path (notify called, visit inserted, 200), missing visitor_name
 * (400), unknown host (404), notifyStaff throws (visit still logged, 500).
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Auth + audit + notify are mocked — we unit-test the handler's orchestration.
vi.mock('../src/auth/middleware', () => ({
  authorizeRequest: () => ({ ok: true, userId: 'test-user' }),
}));
vi.mock('../src/supabase/events', () => ({ logEvent: vi.fn(async () => {}) }));
const notifyStaff = vi.fn(async () => {});
vi.mock('../src/services/notify', () => ({ notifyStaff: (...a: any[]) => notifyStaff(...a) }));

import { handleVisit } from '../src/handlers/visit';

// Fake req that emits the JSON body after the handler attaches its 'end' listener.
function makeReq(body: string | null, headers: Record<string, string> = {}) {
  const listeners: Record<string, (arg?: any) => void> = {};
  const req: any = {
    method: 'POST',
    headers: { authorization: 'Bearer test-token', ...headers },
    on(event: string, cb: (arg?: any) => void) {
      listeners[event] = cb;
      if (event === 'end') {
        setImmediate(() => {
          if (body != null) listeners['data']?.(Buffer.from(body));
          cb();
        });
      }
      return req;
    },
  };
  return req;
}

function makeRes() {
  return {
    statusCode: 0,
    body: '',
    writeHead(status: number) { this.statusCode = status; return this; },
    end(payload?: string) { this.body = payload ?? ''; },
    setHeader() {},
  };
}

// Minimal chainable Supabase mock. `results[table].maybeSingle|single` set outcomes.
function makeSupabase(results: Record<string, any>) {
  const captured: Record<string, any> = {};
  const client: any = {
    from(table: string) {
      const b: any = {
        select: () => b,
        eq: () => b,
        insert: (row: any) => { captured[table] = row; return b; },
        maybeSingle: () => Promise.resolve(results[table]?.maybeSingle ?? { data: null, error: null }),
        single: () => Promise.resolve(results[table]?.single ?? { data: null, error: null }),
      };
      return b;
    },
    _captured: captured,
  };
  return client;
}

const HOST = { id: 'host-1', full_name: 'Alice', notify_channel: 'slack:U0ABC' };

beforeEach(() => notifyStaff.mockClear());

describe('POST /visit', () => {
  it('happy path → inserts visit, notifies host, returns 200', async () => {
    const supabase = makeSupabase({
      staff: { maybeSingle: { data: HOST, error: null } },
      visitor: { single: { data: { id: 'visit-1' }, error: null } },
    });
    const broadcast = vi.fn();
    const res = makeRes();
    await handleVisit(makeReq(JSON.stringify({ visitor_name: 'Bob', host_staff_id: 'host-1' })), res as any, supabase, broadcast);

    expect(res.statusCode).toBe(200);
    const out = JSON.parse(res.body);
    expect(out.ok).toBe(true);
    expect(out.host.full_name).toBe('Alice');
    expect(out.channel_used).toBe('slack');
    expect(notifyStaff).toHaveBeenCalledOnce();
    expect(supabase._captured.visitor.name).toBe('Bob'); // mapped visitor_name → name column
    expect(broadcast).toHaveBeenCalledOnce();
  });

  it('missing visitor_name → 400', async () => {
    const supabase = makeSupabase({ staff: { maybeSingle: { data: HOST, error: null } } });
    const res = makeRes();
    await handleVisit(makeReq(JSON.stringify({ host_staff_id: 'host-1' })), res as any, supabase, vi.fn());
    expect(res.statusCode).toBe(400);
    expect(notifyStaff).not.toHaveBeenCalled();
  });

  it('unknown host_staff_id → 404', async () => {
    const supabase = makeSupabase({ staff: { maybeSingle: { data: null, error: null } } });
    const res = makeRes();
    await handleVisit(makeReq(JSON.stringify({ visitor_name: 'Bob', host_staff_id: 'nope' })), res as any, supabase, vi.fn());
    expect(res.statusCode).toBe(404);
    expect(notifyStaff).not.toHaveBeenCalled();
  });

  it('notifyStaff throws → visit still logged, returns 500', async () => {
    notifyStaff.mockRejectedValueOnce(new Error('slack down'));
    const supabase = makeSupabase({
      staff: { maybeSingle: { data: HOST, error: null } },
      visitor: { single: { data: { id: 'visit-1' }, error: null } },
    });
    const res = makeRes();
    await handleVisit(makeReq(JSON.stringify({ visitor_name: 'Bob', host_staff_id: 'host-1' })), res as any, supabase, vi.fn());

    expect(res.statusCode).toBe(500);
    expect(JSON.parse(res.body).reason).toContain('slack down');
    expect(supabase._captured.visitor).toBeTruthy(); // visit WAS inserted before the failed notify
  });
});
