/**
 * handlers/nav-points.ts — SLAM nav points, brokered through the spine.
 *
 *   GET    /nav-points       list points (sort_order, then created_at)
 *   POST   /nav-points       create a point
 *   PATCH  /nav-points/:id   rename / re-word the arrival announcement
 *   DELETE /nav-points/:id   remove a point
 *
 * WHY: the robot_app used to hit PostgREST directly with the Supabase ANON key
 * baked into the APK, which forced `nav_points` RLS to `USING (true)` with no role
 * restriction (migration 011) — i.e. anyone who pulled the key out of the APK could
 * rewrite where the robot drives. Routing the kiosk through the spine (kiosk-token
 * auth) lets migration 017 take anon off the table entirely.
 *
 * Coordinates are NOT patchable — re-capture a point to move it. That mirrors the
 * robot_app UI and keeps a typo from teleporting a saved destination.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';

const TABLE = 'nav_points';
const KINDS = ['navigation', 'welcome'];

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

async function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

/** A finite number, or null. Rejects NaN/Infinity/strings — bad poses lose the robot. */
function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/**
 * Validate a create payload. Exported for direct unit testing — the coordinate
 * rules are the part worth pinning down.
 */
export function navPointInsert(
  body: Record<string, unknown>
): { ok: true; row: Record<string, unknown> } | { ok: false; reason: string } {
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (!name) return { ok: false, reason: 'name is required' };

  const x = num(body.x);
  const y = num(body.y);
  if (x === null || y === null) return { ok: false, reason: 'x and y must be finite numbers' };

  const kind = typeof body.kind === 'string' && body.kind ? body.kind : 'navigation';
  if (!KINDS.includes(kind)) return { ok: false, reason: `kind must be one of ${KINDS.join(', ')}` };

  const description =
    typeof body.description === 'string' && body.description.trim()
      ? body.description.trim()
      : null;

  return {
    ok: true,
    row: {
      name,
      description,
      x,
      y,
      z: num(body.z) ?? 0,
      rotation: num(body.rotation) ?? 0,
      kind,
      ...(num(body.sort_order) !== null ? { sort_order: num(body.sort_order) } : {}),
    },
  };
}

/**
 * Handle any /nav-points request.
 * Returns false when the route didn't match, so server.ts can fall through.
 */
export async function handleNavPoints(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<boolean> {
  const url = (req.url || '').replace(/\?.*$/, '');
  if (url !== '/nav-points' && !url.startsWith('/nav-points/')) return false;

  const auth = await authorizeRequest(req);
  if (!auth.ok) {
    json(res, auth.status, { ok: false, reason: auth.reason });
    return true;
  }

  const idMatch = url.match(/^\/nav-points\/([^/]+)$/);
  const id = idMatch ? decodeURIComponent(idMatch[1]) : null;

  try {
    if (url === '/nav-points' && req.method === 'GET') {
      const { data, error } = await supabase
        .from(TABLE)
        .select('*')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: true });
      if (error) json(res, 500, { ok: false, reason: error.message });
      else json(res, 200, { ok: true, points: data ?? [] });
      return true;
    }

    if (url === '/nav-points' && req.method === 'POST') {
      let body: Record<string, unknown>;
      try {
        body = JSON.parse((await readBody(req)) || '{}');
      } catch {
        json(res, 400, { ok: false, reason: 'Invalid JSON body' });
        return true;
      }
      const parsed = navPointInsert(body);
      if (!parsed.ok) {
        json(res, 400, { ok: false, reason: parsed.reason });
        return true;
      }
      const { data, error } = await supabase.from(TABLE).insert(parsed.row).select().single();
      if (error) json(res, 500, { ok: false, reason: error.message });
      else json(res, 201, { ok: true, point: data });
      return true;
    }

    if (id && req.method === 'PATCH') {
      let body: Record<string, unknown>;
      try {
        body = JSON.parse((await readBody(req)) || '{}');
      } catch {
        json(res, 400, { ok: false, reason: 'Invalid JSON body' });
        return true;
      }
      // Name and arrival text only — coordinates come from a re-capture.
      const patch: Record<string, unknown> = {};
      if (typeof body.name === 'string' && body.name.trim()) patch.name = body.name.trim();
      if ('description' in body) {
        const d = typeof body.description === 'string' ? body.description.trim() : '';
        patch.description = d || null;
      }
      if (Object.keys(patch).length === 0) {
        json(res, 400, { ok: false, reason: 'nothing to update' });
        return true;
      }
      const { error } = await supabase.from(TABLE).update(patch).eq('id', id);
      if (error) json(res, 500, { ok: false, reason: error.message });
      else json(res, 200, { ok: true });
      return true;
    }

    if (id && req.method === 'DELETE') {
      const { error } = await supabase.from(TABLE).delete().eq('id', id);
      if (error) json(res, 500, { ok: false, reason: error.message });
      else json(res, 200, { ok: true });
      return true;
    }
  } catch (err) {
    json(res, 500, { ok: false, reason: err instanceof Error ? err.message : String(err) });
    return true;
  }

  json(res, 405, { ok: false, reason: 'method not allowed' });
  return true;
}
