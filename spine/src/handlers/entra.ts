/**
 * POST /entra/sync — run the Microsoft Entra ID (Azure AD) → staff sync.
 *
 * Trigger manually (admin app button later, curl/cron today). Same auth model
 * as the other endpoints. 503 with a clear reason when the Entra app
 * registration env isn't configured. Returns the sync summary so the caller
 * sees exactly what changed.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';
import { entraConfigured, syncEntraStaff } from '../services/entra';

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

export async function handleEntraSync(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  if (!entraConfigured()) {
    return json(res, 503, {
      ok: false,
      reason: 'Entra not configured — set ENTRA_TENANT_ID / ENTRA_CLIENT_ID / ENTRA_CLIENT_SECRET',
    });
  }

  try {
    const summary = await syncEntraStaff(supabase);
    await logEvent('entra_sync', { actor: auth.userId, ...summary });
    return json(res, 200, { ok: true, ...summary });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error('[entra/sync] failed:', reason);
    return json(res, 500, { ok: false, reason });
  }
}
