/**
 * POST /visit — visitor self-check-in + host notification.
 *
 * Manual path today (visitor picks the host); face recognition automates the
 * "who" later. DPDP: stores ONLY name + timestamps in `visitor` — no biometrics.
 *
 * Steps: auth (fail-closed) → load host → insert visitor row FIRST (its id is the
 * record anchor) → notifyStaff once → audit + broadcast → return host.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';
import { notifyStaff } from '../services/notify';
import { notifyVisitorArrived } from '../services/push';
import { saveVisitorArrivalSnapshot } from '../captures';
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

const RETENTION_MS = 30 * 24 * 60 * 60 * 1000; // DPDP: purge visitor rows after 30 days

export async function handleVisit(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient,
  broadcast: (event: RobotEvent) => void,
  /** Injected camera frame source (SDK.captureFrame) for the arrival snapshot.
   *  Optional so tests and a camera-less spine still check visitors in. */
  captureFrame?: () => Promise<Buffer | null>
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: any;
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }

  const visitorName = (typeof body.visitor_name === 'string' ? body.visitor_name : '').trim();
  const hostId = body.host_staff_id;
  if (!visitorName) return json(res, 400, { ok: false, reason: 'visitor_name required' });
  if (!hostId) return json(res, 400, { ok: false, reason: 'host_staff_id required' });

  // Optional intake fields (blueprint §07 visitor: name, company, host, purpose).
  // Trimmed + length-capped: these come off a voice transcript, so a garbled STT
  // run must not write a paragraph into the record.
  const optionalText = (v: unknown): string | null => {
    const s = (typeof v === 'string' ? v : '').trim();
    return s ? s.slice(0, 120) : null;
  };
  const company = optionalText(body.company);
  const purpose = optionalText(body.purpose);

  // 1. Load the host staff record.
  const { data: host, error: hostErr } = await supabase
    .from('staff')
    .select('id, full_name, notify_channel')
    .eq('id', hostId)
    .maybeSingle();
  if (hostErr) return json(res, 500, { ok: false, reason: hostErr.message });
  if (!host) return json(res, 404, { ok: false, reason: 'Host staff not found' });

  // 2. Insert the visitor row FIRST (no biometrics; retention-bound). Its id is
  //    the anchor — the visit is recorded before we attempt any outbound send.
  const { data: visit, error: insErr } = await supabase
    .from('visitor')
    .insert({
      name: visitorName,
      company,
      purpose,
      host_staff_id: host.id,
      arrived_at: new Date().toISOString(),
      purge_after: new Date(Date.now() + RETENTION_MS).toISOString(),
    })
    .select('id')
    .single();
  if (insErr || !visit) {
    return json(res, 500, { ok: false, reason: insErr?.message ?? 'Failed to log visit' });
  }

  // 2b. Arrival snapshot (F1) — best-effort and non-blocking. A plain arrival
  //     photo on the visitor row, never a biometric: it is not embedded, not
  //     matched, and dies with the row at purge_after. Off by default so a
  //     deployment opts in (DPDP notice must be posted at reception first).
  if (process.env.ARRIVAL_SNAPSHOT_ENABLED === 'true' && captureFrame) {
    void (async () => {
      try {
        const frame = await captureFrame();
        if (!frame) return void console.warn('[visit] arrival snapshot: no frame from camera');
        await saveVisitorArrivalSnapshot(supabase, frame, visit.id);
      } catch (err) {
        console.warn('[visit] arrival snapshot failed:', err instanceof Error ? err.message : String(err));
      }
    })();
  }

  const channelType = (host.notify_channel ?? '').split(':')[0] || 'none';

  // 3. Notify the host exactly once. If the send fails, the visit is still logged.
  try {
    await notifyStaff({ full_name: host.full_name, notify_channel: host.notify_channel }, visitorName);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[visit] notifyStaff failed:', message);
    return json(res, 500, {
      ok: false,
      reason: `Visit logged but notification failed: ${message}`,
      host: { id: host.id, full_name: host.full_name },
    });
  }

  // 4. Audit + broadcast a live event for the admin app.
  await logEvent('visitor_arrived', {
    actor: auth.userId,
    visitor_id: visit.id,
    visitor_name: visitorName,
    company,
    purpose,
    host_staff_id: host.id,
    channel: channelType,
  });
  broadcast({
    type: 'visitor_arrived',
    payload: {
      visitor_name: visitorName,
      company,
      purpose,
      host: { id: host.id, full_name: host.full_name },
      channel: channelType,
    },
  });

  // 5. Best-effort push to the mobile admin app (#90). Never throws — a push
  // failure must not affect the check-in response.
  void notifyVisitorArrived(supabase, visitorName, host.full_name);

  return json(res, 200, {
    ok: true,
    host: { id: host.id, full_name: host.full_name },
    channel_used: channelType,
  });
}
