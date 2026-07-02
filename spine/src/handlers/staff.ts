/**
 * Staff management endpoints — list / update / delete enrolled staff.
 *
 *   GET    /staff          → list staff with embedding counts
 *   PATCH  /staff/{id}     → update full_name / phone / person_type / role
 *   DELETE /staff/{id}     → delete staff (cascade-erases face embeddings = DPDP erasure)
 *
 * Same auth model as /enroll (JWT, with a dev test-token bypass). Deletions are
 * audit-logged because they erase biometric data.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';
import { deskColumns } from './enroll';

// Signed-URL lifetime for staff thumbnails. The Gallery re-fetches /staff on each
// open/refresh, so a short TTL is fine and keeps face images from leaking via stale links.
const SIGNED_URL_TTL_SECONDS = 60 * 60; // 1 hour

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

/** GET /staff — list with embedding counts. */
export async function handleListStaff(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  const { data: staff, error } = await supabase
    .from('staff')
    .select('id, full_name, phone, person_type, role, active, created_at, photo_path, desk_x, desk_y, desk_z, desk_rotation, desk_captured_at')
    .order('created_at', { ascending: true });
  if (error) return json(res, 500, { ok: false, reason: error.message });

  const { data: embs } = await supabase.from('staff_face_embedding').select('staff_id');
  const counts: Record<string, number> = {};
  for (const e of embs ?? []) counts[e.staff_id] = (counts[e.staff_id] ?? 0) + 1;

  // Mint short-lived signed URLs for the private display thumbnails so the robot
  // Gallery + web admin can render faces without exposing the bucket publicly.
  const paths = (staff ?? [])
    .map(s => (s as { photo_path?: string }).photo_path)
    .filter((p): p is string => !!p);
  const signedByPath: Record<string, string> = {};
  if (paths.length) {
    const { data: signed } = await supabase.storage
      .from('staff-photos')
      .createSignedUrls(paths, SIGNED_URL_TTL_SECONDS);
    for (const s of signed ?? []) {
      if (s.path && s.signedUrl && !s.error) signedByPath[s.path] = s.signedUrl;
    }
  }

  const result = (staff ?? []).map(s => {
    const { photo_path, ...rest } = s as Record<string, unknown> & { photo_path?: string };
    return {
      ...rest,
      embedding_count: counts[s.id] ?? 0,
      photo_url: photo_path ? signedByPath[photo_path] ?? null : null,
    };
  });
  return json(res, 200, { ok: true, staff: result });
}

/** PATCH /staff/{id} — update editable fields. */
export async function handleUpdateStaff(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient,
  id: string
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: any;
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }

  const update: Record<string, unknown> = {};
  if (body.full_name !== undefined) update.full_name = body.full_name;
  if (body.phone !== undefined) update.phone = body.phone;
  if (body.person_type !== undefined) update.person_type = body.person_type;
  if (body.role !== undefined) update.role = body.role;
  // Desk pose: set from a captured SLAM pose, or clear it with desk_pose: null.
  if (body.desk_pose !== undefined) {
    const desk = deskColumns(body.desk_pose);
    if (desk) {
      Object.assign(update, desk);
    } else if (body.desk_pose === null) {
      Object.assign(update, {
        desk_x: null, desk_y: null, desk_z: null, desk_rotation: null, desk_captured_at: null,
      });
    }
  }
  if (Object.keys(update).length === 0) {
    return json(res, 400, { ok: false, reason: 'No updatable fields provided' });
  }

  const { error } = await supabase.from('staff').update(update).eq('id', id);
  if (error) return json(res, 500, { ok: false, reason: error.message });

  await logEvent('staff_updated', { actor: auth.userId, staff_id: id, fields: Object.keys(update) });
  return json(res, 200, { ok: true });
}

/** DELETE /staff/{id} — remove staff + cascade-erase embeddings (DPDP). */
export async function handleDeleteStaff(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient,
  id: string
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  // Capture identity + count for the audit trail before deleting.
  const { data: s } = await supabase.from('staff').select('full_name').eq('id', id).maybeSingle();
  const { count } = await supabase
    .from('staff_face_embedding')
    .select('id', { count: 'exact', head: true })
    .eq('staff_id', id);

  const { error } = await supabase.from('staff').delete().eq('id', id); // cascade deletes embeddings
  if (error) return json(res, 500, { ok: false, reason: error.message });

  // Erase the display thumbnail too (best-effort — the DB record is already gone).
  await supabase.storage.from('staff-photos').remove([`${id}.jpg`]).catch(() => {});

  await logEvent('staff_deleted', {
    actor: auth.userId,
    staff_id: id,
    full_name: s?.full_name ?? null,
    embeddings_erased: count ?? 0,
  });
  return json(res, 200, { ok: true, embeddings_erased: count ?? 0 });
}
