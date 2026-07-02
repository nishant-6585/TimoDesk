/**
 * POST /ask — text-first voice-brain endpoint (T6/T7).
 *
 * Body: { question: string }
 * → { ok, answer, source: 'kb'|'claude'|'handoff', similarity }
 *
 * Same auth model as the other endpoints (JWT / kiosk token / dev bypass). This
 * is the "prove the brain before the ears" surface — the robot's STT feeds it a
 * transcript later; for now it answers typed questions.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { askQuestion } from '../services/rag';

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

export async function handleAsk(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  const auth = await authorizeRequest(req);
  if (!auth.ok) return json(res, auth.status, { ok: false, reason: auth.reason });

  let body: { question?: unknown };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { ok: false, reason: 'Invalid JSON body' });
  }

  const question = typeof body.question === 'string' ? body.question.trim() : '';
  if (!question) return json(res, 400, { ok: false, reason: 'question is required' });

  try {
    const result = await askQuestion(supabase, question);
    return json(res, 200, {
      ok: true,
      answer: result.answer,
      source: result.source,
      similarity: result.similarity,
    });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    console.error('[ask] failed:', reason);
    return json(res, 500, { ok: false, reason });
  }
}
