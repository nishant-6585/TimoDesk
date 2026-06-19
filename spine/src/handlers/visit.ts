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
  broadcast: (event: RobotEvent) => void
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
      host_staff_id: host.id,
      arrived_at: new Date().toISOString(),
      purge_after: new Date(Date.now() + RETENTION_MS).toISOString(),
    })
    .select('id')
    .single();
  if (insErr || !visit) {
    return json(res, 500, { ok: false, reason: insErr?.message ?? 'Failed to log visit' });
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
    host_staff_id: host.id,
    channel: channelType,
  });
  broadcast({
    type: 'visitor_arrived',
    payload: {
      visitor_name: visitorName,
      host: { id: host.id, full_name: host.full_name },
      channel: channelType,
    },
  });

  return json(res, 200, {
    ok: true,
    host: { id: host.id, full_name: host.full_name },
    channel_used: channelType,
  });
}
