/**
 * POST /check-face — duplicate-enrollment guard.
 *
 * Takes one captured frame, computes its 128-d embedding via the SHARED
 * extractEmbedding (same face-api path as enrollment), and checks whether it
 * matches an already-enrolled person by nearest-neighbour L2 against
 * FACE_CONFIG.threshold. The UI calls this before saving so it can warn
 * "looks like <name> is already enrolled".
 *
 * Read-only: never writes. Same auth as /enroll (JWT + dev test-token).
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { extractEmbedding } from '../services/face-embedding';
import { FACE_CONFIG } from '../config/face-recognition';

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise(resolve => {
    let b = '';
    req.on('data', c => (b += c.toString()));
    req.on('end', () => resolve(b));
  });
}

function l2(a: number[], b: number[]): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    const d = a[i] - b[i];
    s += d * d;
  }
  return Math.sqrt(s);
}

function parseEmbedding(raw: unknown): number[] | null {
  if (Array.isArray(raw)) return raw as number[];
  if (typeof raw === 'string') {
    try {
      const arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr : null;
    } catch {
      return null;
    }
  }
  return null;
}

export async function handleCheckFace(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) {
    res.writeHead(auth.status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, reason: auth.reason }));
    return;
  }

  let body: any;
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, reason: 'Invalid JSON body' }));
    return;
  }

  let imageBuffer: Buffer;
  try {
    imageBuffer = Buffer.from(body.image_base64 ?? '', 'base64');
  } catch {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, reason: 'Invalid base64 image' }));
    return;
  }

  const emb = await extractEmbedding(imageBuffer);
  if (!emb.ok || !emb.embedding) {
    // No usable face → can't compare; let enrollment proceed (not a duplicate signal).
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, match: false, reason: emb.error ?? 'no face' }));
    return;
  }

  const { data: rows, error } = await supabase
    .from('staff_face_embedding')
    .select('staff_id, embedding, staff:staff_id(full_name)');
  if (error) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, reason: error.message }));
    return;
  }

  // Nearest enrolled embedding (same metric as the recognizer).
  let bestDist = Infinity;
  let bestName = '';
  let bestStaffId = '';
  for (const r of rows ?? []) {
    const e = parseEmbedding((r as any).embedding);
    if (!e || e.length !== 128) continue;
    const d = l2(emb.embedding, e);
    if (d < bestDist) {
      bestDist = d;
      bestName = (r as any).staff?.full_name ?? '';
      bestStaffId = (r as any).staff_id;
    }
  }

  const match = bestDist < FACE_CONFIG.threshold;
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(
    JSON.stringify({
      ok: true,
      match,
      name: match ? bestName : null,
      staff_id: match ? bestStaffId : null,
      distance: Number.isFinite(bestDist) ? Number(bestDist.toFixed(3)) : null,
    })
  );
}
