/**
 * POST /voice/log — log a completed voice conversation to Supabase (#80).
 *
 * The full STT → LLM → TTS turn happens inside the ElevenLabs Conversational AI
 * session on the robot; spine only persists the resulting transcript for audit +
 * analytics. DPDP: short 7-day retention (transcript must be PII-scrubbed before
 * insert — same contract as the `conversation` table comment).
 *
 * Steps: auth (fail-closed) → validate transcript → insert conversation row →
 * audit event → return id.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';

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

const RETENTION_MS = 7 * 24 * 60 * 60 * 1000; // DPDP: purge conversations after 7 days

export async function handleVoiceLog(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: any;
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }

  const transcript = Array.isArray(body.transcript) ? body.transcript : [];
  // Interaction ledger entries (role:'action', kind, detail, t) — what the
  // robot decided/did around the spoken turns. Stored in the SAME jsonb
  // stream so analysis reads one chronological record per interaction.
  const actions = Array.isArray(body.actions) ? body.actions : [];
  const merged = [...transcript, ...actions];
  if (merged.length === 0) {
    return json(res, 400, { ok: false, reason: 'transcript or actions must be a non-empty array' });
  }

  const resolvedBy = typeof body.resolved_by === 'string' ? body.resolved_by : 'elevenlabs';
  const visitorId = typeof body.visitor_id === 'string' ? body.visitor_id : null;

  const { data: row, error } = await supabase
    .from('conversation')
    .insert({
      transcript: merged, // jsonb — PII scrubbed upstream
      resolved_by: resolvedBy,
      visitor_id: visitorId,
      purge_after: new Date(Date.now() + RETENTION_MS).toISOString(),
    })
    .select('id')
    .single();

  if (error || !row) {
    return json(res, 500, { ok: false, reason: error?.message ?? 'Failed to log conversation' });
  }

  await logEvent('conversation', {
    actor: auth.userId,
    conversation_id: row.id,
    turn_count: transcript.length,
    resolved_by: resolvedBy,
  });

  return json(res, 200, { ok: true, id: row.id });
}
