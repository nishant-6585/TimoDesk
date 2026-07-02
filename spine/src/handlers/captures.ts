/**
 * Capture endpoints — admin snapshot gallery (F7).
 *
 *   GET /captures → list recent admin snapshots with short-lived signed image URLs
 *
 * Same auth model as /staff (JWT, with the dev test-token bypass). The heavy
 * lifting (query + signed-URL minting) lives in ../captures so it's unit-testable.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { listSnapshots } from '../captures';

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

/** GET /captures — recent admin snapshots, newest first. */
export async function handleListCaptures(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  try {
    const captures = await listSnapshots(supabase);
    return json(res, 200, { ok: true, captures });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    return json(res, 500, { ok: false, reason });
  }
}
