/**
 * POST /xboom/lead — showroom order/enquiry capture → XBoom Workflow OS.
 *
 * The robot's face screen (Order / Enquiry FABs) collects a visitor's contact
 * + requirement and sends it here; the spine forwards it into XBoom OS's sales
 * pipeline (enquiries table → AI lead scoring → auto follow-up task). Brokered
 * here so the kiosk never holds XBoom credentials — same reason nav points are.
 *
 * Steps: auth (fail-closed) → validate + length-cap → forward to XBoom →
 * audit + broadcast. If XBoom isn't configured, 503 with a clear reason.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';
import {
  fetchXboomCatalog,
  submitLeadToXboom,
  xboomConfigured,
  XboomLead,
} from '../services/xboom';
import { RobotEvent } from '../types';

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise(resolve => {
    let b = '';
    req.on('data', c => (b += c.toString()));
    req.on('end', () => resolve(b));
  });
}

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

/** Trim + cap kiosk text — a stray paste or garbled input must not write a
 *  novel into the CRM. Returns null when empty. */
function capped(v: unknown, max: number): string | null {
  const s = (typeof v === 'string' ? v : '').trim();
  return s ? s.slice(0, max) : null;
}

export async function handleXboomLead(
  req: IncomingMessage,
  res: ServerResponse,
  broadcast: (event: RobotEvent) => void
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  if (!xboomConfigured()) {
    return json(res, 503, {
      ok: false,
      reason: 'XBoom Workflow integration not configured (set XBOOM_SUPABASE_URL + XBOOM_API_KEY)',
    });
  }

  let body: any;
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }

  const kind = body.kind === 'order' ? 'order' : body.kind === 'enquiry' ? 'enquiry' : null;
  if (!kind) return json(res, 400, { ok: false, reason: "kind must be 'order' or 'enquiry'" });

  const name = capped(body.name, 120);
  const phone = capped(body.phone, 20);
  const product = capped(body.product, 300);
  if (!name) return json(res, 400, { ok: false, reason: 'name required' });
  if (!phone) return json(res, 400, { ok: false, reason: 'phone required' });
  if (!product) return json(res, 400, { ok: false, reason: 'product required' });

  const lead: XboomLead = {
    kind,
    name,
    phone,
    product,
    productCode: capped(body.product_code, 64),
    email: capped(body.email, 120),
    quantity:
      typeof body.quantity === 'number' && Number.isFinite(body.quantity)
        ? Math.max(1, Math.min(99, Math.round(body.quantity)))
        : null,
    notes: capped(body.notes, 500),
  };

  const result = await submitLeadToXboom(lead);
  if (!result.ok) {
    console.error('[xboom] lead forward failed:', result.reason);
    return json(res, 502, { ok: false, reason: result.reason ?? 'XBoom submission failed' });
  }

  // Audit + live event for the admin app. PII stays out of the broadcast
  // payload (admin sees the full record in XBoom OS itself).
  await logEvent('xboom_lead_created', {
    actor: auth.userId,
    kind,
    product,
    reference: result.reference ?? null,
  });
  broadcast({
    type: 'xboom_lead_created',
    payload: { kind, product, reference: result.reference ?? null },
  });

  return json(res, 200, { ok: true, reference: result.reference ?? null });
}

/**
 * GET /xboom/catalog?search=&limit=&offset= — kiosk product browser, proxied
 * (and TTL-cached) from XBoom's robot-catalog function so the robot never
 * holds XBoom credentials. Read-only; no audit event (it's just browsing).
 */
export async function handleXboomCatalog(
  req: IncomingMessage,
  res: ServerResponse
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  if (!xboomConfigured()) {
    return json(res, 503, {
      ok: false,
      reason: 'XBoom Workflow integration not configured (set XBOOM_LEAD_ENDPOINT + XBOOM_WEBHOOK_SECRET)',
    });
  }

  const url = new URL(req.url ?? '/', 'http://localhost');
  const search = (url.searchParams.get('search') ?? '').trim().slice(0, 120);
  // Absent params keep their defaults — Number(null) is 0, so parse only when present.
  const intParam = (name: string, fallback: number, min: number, max: number): number => {
    const raw = url.searchParams.get(name);
    if (raw === null || raw === '') return fallback;
    const n = Number(raw);
    return Number.isFinite(n) ? Math.max(min, Math.min(max, Math.round(n))) : fallback;
  };
  const limit = intParam('limit', 30, 1, 50);
  const offset = intParam('offset', 0, 0, 10_000);

  const result = await fetchXboomCatalog({ search, limit, offset });
  if (!result.ok) {
    console.error('[xboom] catalog fetch failed:', result.reason);
    return json(res, 502, { ok: false, reason: result.reason ?? 'XBoom catalog unavailable' });
  }
  return json(res, 200, { ok: true, products: result.products, total: result.total });
}
