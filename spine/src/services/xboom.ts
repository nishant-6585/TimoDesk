/**
 * services/xboom.ts — forward showroom leads into XBoom Workflow OS.
 *
 * Transport: POST to the `robot-lead-incoming` Supabase edge function in the
 * XBoom Workflow project, signed with HMAC-SHA256 over the raw body in an
 * `x-xbm-signature: sha256=<hex>` header — the same scheme XBoom OS already
 * uses for its WordPress leads webhook (leads-incoming), so the receiving side
 * is house-pattern. Config via env:
 *   XBOOM_LEAD_ENDPOINT  full URL of the edge function
 *   XBOOM_WEBHOOK_SECRET shared secret (ROBOT_WEBHOOK_SECRET on the XBoom side)
 * Both unset → xboomConfigured() false and the /xboom/lead route 503s.
 */

import { createHmac } from 'crypto';

export interface XboomLead {
  kind: 'order' | 'enquiry';
  name: string;
  phone: string;
  product: string;
  email: string | null;
  quantity: number | null;
  notes: string | null;
}

export interface XboomSubmitResult {
  ok: boolean;
  /** XBoom enquiry id when the insert succeeded. */
  reference?: string;
  reason?: string;
}

export function xboomConfigured(): boolean {
  return Boolean(process.env.XBOOM_LEAD_ENDPOINT && process.env.XBOOM_WEBHOOK_SECRET);
}

export async function submitLeadToXboom(lead: XboomLead): Promise<XboomSubmitResult> {
  const endpoint = process.env.XBOOM_LEAD_ENDPOINT;
  const secret = process.env.XBOOM_WEBHOOK_SECRET;
  if (!endpoint || !secret) return { ok: false, reason: 'XBoom integration not configured' };

  const body = JSON.stringify({
    kind: lead.kind,
    name: lead.name,
    phone: lead.phone,
    product: lead.product,
    ...(lead.email ? { email: lead.email } : {}),
    ...(lead.quantity != null ? { quantity: lead.quantity } : {}),
    ...(lead.notes ? { notes: lead.notes } : {}),
  });
  const signature = createHmac('sha256', secret).update(body).digest('hex');

  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10_000);
    let res: Response;
    try {
      res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-xbm-signature': `sha256=${signature}`,
        },
        body,
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    let payload: any = {};
    try {
      payload = await res.json();
    } catch {
      /* non-JSON error body — fall through to status handling */
    }
    if (res.ok && payload?.ok === true) {
      return { ok: true, reference: typeof payload.id === 'string' ? payload.id : undefined };
    }
    return {
      ok: false,
      reason: typeof payload?.error === 'string' ? payload.error : `XBoom HTTP ${res.status}`,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, reason: `XBoom unreachable: ${message}` };
  }
}
