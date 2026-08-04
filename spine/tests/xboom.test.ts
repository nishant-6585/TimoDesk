/**
 * tests/xboom.test.ts — POST /xboom/lead (showroom Order/Enquiry → XBoom OS)
 *
 * Covers: happy path (forward + audit + broadcast), validation failures,
 * unconfigured integration (503), and upstream failure (502).
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { EventEmitter } from 'events';

vi.mock('../src/auth/middleware', () => ({
  authorizeRequest: () => ({ ok: true, userId: 'test-user' }),
}));
vi.mock('../src/supabase/events', () => ({ logEvent: vi.fn(async () => {}) }));

const submitLeadToXboom = vi.fn();
const fetchXboomCatalog = vi.fn();
const xboomConfigured = vi.fn(() => true);
vi.mock('../src/services/xboom', () => ({
  submitLeadToXboom: (...args: unknown[]) => submitLeadToXboom(...args),
  fetchXboomCatalog: (...args: unknown[]) => fetchXboomCatalog(...args),
  xboomConfigured: () => xboomConfigured(),
}));

import { handleXboomLead, handleXboomCatalog } from '../src/handlers/xboom';
import { logEvent } from '../src/supabase/events';

function makeReq(body: unknown) {
  const req = new EventEmitter() as any;
  req.headers = { authorization: 'Bearer test-token' };
  process.nextTick(() => {
    req.emit('data', typeof body === 'string' ? body : JSON.stringify(body));
    req.emit('end');
  });
  return req;
}

function makeRes() {
  return {
    statusCode: 0,
    body: '',
    writeHead(status: number) { this.statusCode = status; return this; },
    end(payload?: string) { this.body = payload ?? ''; },
  };
}

const validLead = {
  kind: 'enquiry',
  name: 'Asha Rao',
  phone: '+91 98765 43210',
  product: 'Agriculture drone',
};

beforeEach(() => {
  submitLeadToXboom.mockReset();
  fetchXboomCatalog.mockReset();
  xboomConfigured.mockReturnValue(true);
  vi.mocked(logEvent).mockClear();
});

describe('POST /xboom/lead', () => {
  it('forwards a valid enquiry, audits, and broadcasts (no PII in broadcast)', async () => {
    submitLeadToXboom.mockResolvedValue({ ok: true, reference: 'ENQ-123' });
    const res = makeRes();
    const broadcast = vi.fn();

    await handleXboomLead(makeReq({ ...validLead, email: 'a@b.com', notes: 'wants demo' }), res as any, broadcast);

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ ok: true, reference: 'ENQ-123' });

    expect(submitLeadToXboom).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: 'enquiry',
        name: 'Asha Rao',
        phone: '+91 98765 43210',
        product: 'Agriculture drone',
        email: 'a@b.com',
        notes: 'wants demo',
      })
    );

    expect(broadcast).toHaveBeenCalledTimes(1);
    const event = broadcast.mock.calls[0][0];
    expect(event.type).toBe('xboom_lead_created');
    // Contact details must not ride the admin broadcast.
    expect(JSON.stringify(event.payload)).not.toContain('98765');
    expect(JSON.stringify(event.payload)).not.toContain('a@b.com');

    expect(logEvent).toHaveBeenCalledWith('xboom_lead_created', expect.objectContaining({ kind: 'enquiry' }));
  });

  it('clamps order quantity into 1..99', async () => {
    submitLeadToXboom.mockResolvedValue({ ok: true });
    const res = makeRes();

    await handleXboomLead(
      makeReq({ ...validLead, kind: 'order', quantity: 500 }),
      res as any,
      vi.fn()
    );

    expect(res.statusCode).toBe(200);
    expect(submitLeadToXboom).toHaveBeenCalledWith(expect.objectContaining({ kind: 'order', quantity: 99 }));
  });

  it('rejects a missing phone with 400 and never calls XBoom', async () => {
    const res = makeRes();

    await handleXboomLead(makeReq({ ...validLead, phone: '  ' }), res as any, vi.fn());

    expect(res.statusCode).toBe(400);
    expect(JSON.parse(res.body).reason).toMatch(/phone/);
    expect(submitLeadToXboom).not.toHaveBeenCalled();
  });

  it('rejects an unknown kind with 400', async () => {
    const res = makeRes();

    await handleXboomLead(makeReq({ ...validLead, kind: 'complaint' }), res as any, vi.fn());

    expect(res.statusCode).toBe(400);
    expect(submitLeadToXboom).not.toHaveBeenCalled();
  });

  it('returns 503 when the XBoom integration is not configured', async () => {
    xboomConfigured.mockReturnValue(false);
    const res = makeRes();

    await handleXboomLead(makeReq(validLead), res as any, vi.fn());

    expect(res.statusCode).toBe(503);
    expect(submitLeadToXboom).not.toHaveBeenCalled();
  });

  it('passes a catalog product_code through to the service', async () => {
    submitLeadToXboom.mockResolvedValue({ ok: true });
    const res = makeRes();

    await handleXboomLead(makeReq({ ...validLead, product_code: 'AGR-X10' }), res as any, vi.fn());

    expect(res.statusCode).toBe(200);
    expect(submitLeadToXboom).toHaveBeenCalledWith(expect.objectContaining({ productCode: 'AGR-X10' }));
  });

  it('returns 502 (and no broadcast) when the upstream submission fails', async () => {
    submitLeadToXboom.mockResolvedValue({ ok: false, reason: 'RLS denied' });
    const res = makeRes();
    const broadcast = vi.fn();

    await handleXboomLead(makeReq(validLead), res as any, broadcast);

    expect(res.statusCode).toBe(502);
    expect(JSON.parse(res.body).reason).toBe('RLS denied');
    expect(broadcast).not.toHaveBeenCalled();
    expect(logEvent).not.toHaveBeenCalled();
  });
});

describe('GET /xboom/catalog', () => {
  function makeGetReq(query: string) {
    return { url: `/xboom/catalog${query}`, headers: { authorization: 'Bearer test-token' } } as any;
  }

  it('parses + clamps query params and returns the products', async () => {
    fetchXboomCatalog.mockResolvedValue({
      ok: true,
      products: [{ product_name: 'Nano drone', woo_sku: 'ND-1' }],
      total: 1,
    });
    const res = makeRes();

    await handleXboomCatalog(makeGetReq('?search=drone&limit=500&offset=-3'), res as any);

    expect(res.statusCode).toBe(200);
    const out = JSON.parse(res.body);
    expect(out.ok).toBe(true);
    expect(out.products).toHaveLength(1);
    expect(out.total).toBe(1);
    expect(fetchXboomCatalog).toHaveBeenCalledWith({ search: 'drone', limit: 50, offset: 0 });
  });

  it('defaults limit/offset when absent', async () => {
    fetchXboomCatalog.mockResolvedValue({ ok: true, products: [], total: 0 });
    const res = makeRes();

    await handleXboomCatalog(makeGetReq(''), res as any);

    expect(fetchXboomCatalog).toHaveBeenCalledWith({ search: '', limit: 30, offset: 0 });
  });

  it('returns 503 when unconfigured', async () => {
    xboomConfigured.mockReturnValue(false);
    const res = makeRes();

    await handleXboomCatalog(makeGetReq('?search=x'), res as any);

    expect(res.statusCode).toBe(503);
    expect(fetchXboomCatalog).not.toHaveBeenCalled();
  });

  it('returns 502 when the upstream catalog fetch fails', async () => {
    fetchXboomCatalog.mockResolvedValue({ ok: false, reason: 'XBoom unreachable: timeout' });
    const res = makeRes();

    await handleXboomCatalog(makeGetReq('?search=x'), res as any);

    expect(res.statusCode).toBe(502);
    expect(JSON.parse(res.body).reason).toContain('unreachable');
  });
});
