/**
 * tests/xboom-service.test.ts — services/xboom (HMAC-signed forward to the
 * XBoom Workflow OS robot-lead-incoming edge function).
 *
 * Covers: signature correctness (verifiable with the same secret), payload
 * shape, unconfigured guard, upstream error mapping, and network failure.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createHmac } from 'crypto';

import { submitLeadToXboom, xboomConfigured, XboomLead } from '../src/services/xboom';

const lead: XboomLead = {
  kind: 'order',
  name: 'Asha Rao',
  phone: '+91 98765 43210',
  product: 'Agriculture drone',
  email: 'asha@example.com',
  quantity: 2,
  notes: 'wants a demo first',
};

const ENDPOINT = 'https://xboom.example/functions/v1/robot-lead-incoming';
const SECRET = 'shared-secret';

beforeEach(() => {
  process.env.XBOOM_LEAD_ENDPOINT = ENDPOINT;
  process.env.XBOOM_WEBHOOK_SECRET = SECRET;
});

afterEach(() => {
  delete process.env.XBOOM_LEAD_ENDPOINT;
  delete process.env.XBOOM_WEBHOOK_SECRET;
  vi.unstubAllGlobals();
});

describe('xboomConfigured', () => {
  it('is true only when endpoint AND secret are set', () => {
    expect(xboomConfigured()).toBe(true);
    delete process.env.XBOOM_WEBHOOK_SECRET;
    expect(xboomConfigured()).toBe(false);
    process.env.XBOOM_WEBHOOK_SECRET = SECRET;
    delete process.env.XBOOM_LEAD_ENDPOINT;
    expect(xboomConfigured()).toBe(false);
  });
});

describe('submitLeadToXboom', () => {
  it('signs the exact raw body with HMAC-SHA256 and returns the enquiry id', async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ ok: true, id: 'enq-42' }), { status: 200 })
    );
    vi.stubGlobal('fetch', fetchMock);

    const result = await submitLeadToXboom(lead);

    expect(result).toEqual({ ok: true, reference: 'enq-42' });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(ENDPOINT);

    // The signature must verify against the raw body actually sent.
    const rawBody = init.body as string;
    const expected = `sha256=${createHmac('sha256', SECRET).update(rawBody).digest('hex')}`;
    expect((init.headers as Record<string, string>)['x-xbm-signature']).toBe(expected);

    const parsed = JSON.parse(rawBody);
    expect(parsed).toEqual({
      kind: 'order',
      name: 'Asha Rao',
      phone: '+91 98765 43210',
      product: 'Agriculture drone',
      email: 'asha@example.com',
      quantity: 2,
      notes: 'wants a demo first',
    });
  });

  it('omits empty optional fields from the payload', async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ ok: true }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await submitLeadToXboom({ ...lead, email: null, quantity: null, notes: null });

    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    const parsed = JSON.parse(init.body as string);
    expect(parsed).not.toHaveProperty('email');
    expect(parsed).not.toHaveProperty('quantity');
    expect(parsed).not.toHaveProperty('notes');
  });

  it('fails without calling fetch when unconfigured', async () => {
    delete process.env.XBOOM_WEBHOOK_SECRET;
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const result = await submitLeadToXboom(lead);

    expect(result.ok).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("maps the upstream function's error message through", async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response(JSON.stringify({ ok: false, error: 'invalid signature' }), { status: 401 })
    ));

    const result = await submitLeadToXboom(lead);

    expect(result).toEqual({ ok: false, reason: 'invalid signature' });
  });

  it('reports a clean reason when XBoom is unreachable', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => {
      throw new Error('ECONNREFUSED');
    }));

    const result = await submitLeadToXboom(lead);

    expect(result.ok).toBe(false);
    expect(result.reason).toContain('XBoom unreachable');
  });
});
