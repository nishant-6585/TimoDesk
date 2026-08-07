/**
 * handlers/voice-commands.ts — the voice command catalog, brokered by the spine.
 *
 *   GET    /voice-commands       list commands (sort_order, then created_at)
 *   POST   /voice-commands       create a command
 *   PATCH  /voice-commands/:id   edit label / phrases / enabled / confirm / order
 *   DELETE /voice-commands/:id   remove a command
 *
 * Step 4 of the configurable voice-command architecture: the robot's command set
 * is CONFIGURATION, not hardcoded Dart. The Admin "Voice Commands" screen edits
 * this catalog; the spine serves it to the robot (on-device reflex patterns) and
 * to the ElevenLabs agent (tool examples). Brokered like nav_points post-017 —
 * the table has no anon/authenticated RLS, so every read/write goes through here.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';

const TABLE = 'voice_commands';
const SKILLS = ['system', 'navigation', 'social', 'reception', 'persona'];
const TIERS = ['reflex', 'llm'];

function json(res: ServerResponse, status: number, payload: unknown): void {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

/** A clean non-empty string array, or []. Drops blanks + trims. */
function phrases(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((s): s is string => typeof s === 'string')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 0);
}

/**
 * Validate a create payload. Exported for unit testing — the phrase/skill rules
 * are the part worth pinning down (a blank intent or empty phrase list makes a
 * dead command that silently never fires).
 */
export function voiceCommandInsert(
  body: Record<string, unknown>
): { ok: true; row: Record<string, unknown> } | { ok: false; reason: string } {
  const intent = typeof body.intent === 'string' ? body.intent.trim() : '';
  if (!intent) return { ok: false, reason: 'intent is required' };

  const label = typeof body.label === 'string' ? body.label.trim() : '';
  if (!label) return { ok: false, reason: 'label is required' };

  const skill = typeof body.skill === 'string' && body.skill ? body.skill : 'system';
  if (!SKILLS.includes(skill)) {
    return { ok: false, reason: `skill must be one of ${SKILLS.join(', ')}` };
  }

  const tier = typeof body.tier === 'string' && body.tier ? body.tier : 'reflex';
  if (!TIERS.includes(tier)) {
    return { ok: false, reason: `tier must be one of ${TIERS.join(', ')}` };
  }

  const examplePhrases = phrases(body.example_phrases);
  if (examplePhrases.length === 0) {
    return { ok: false, reason: 'at least one example phrase is required' };
  }

  return {
    ok: true,
    row: {
      intent,
      label,
      skill,
      tier,
      example_phrases: examplePhrases,
      confirm: body.confirm === true,
      enabled: body.enabled !== false,
      ...(typeof body.sort_order === 'number' && Number.isFinite(body.sort_order)
        ? { sort_order: body.sort_order }
        : {}),
    },
  };
}

/** Validate a PATCH: only the editable fields, all optional, at least one set. */
export function voiceCommandPatch(
  body: Record<string, unknown>
): { ok: true; patch: Record<string, unknown> } | { ok: false; reason: string } {
  const patch: Record<string, unknown> = {};

  if (typeof body.label === 'string') {
    const label = body.label.trim();
    if (!label) return { ok: false, reason: 'label cannot be blank' };
    patch.label = label;
  }
  if ('example_phrases' in body) {
    const p = phrases(body.example_phrases);
    if (p.length === 0) return { ok: false, reason: 'at least one example phrase is required' };
    patch.example_phrases = p;
  }
  if (typeof body.skill === 'string') {
    if (!SKILLS.includes(body.skill)) {
      return { ok: false, reason: `skill must be one of ${SKILLS.join(', ')}` };
    }
    patch.skill = body.skill;
  }
  if (typeof body.tier === 'string') {
    if (!TIERS.includes(body.tier)) {
      return { ok: false, reason: `tier must be one of ${TIERS.join(', ')}` };
    }
    patch.tier = body.tier;
  }
  if (typeof body.enabled === 'boolean') patch.enabled = body.enabled;
  if (typeof body.confirm === 'boolean') patch.confirm = body.confirm;
  if (typeof body.sort_order === 'number' && Number.isFinite(body.sort_order)) {
    patch.sort_order = body.sort_order;
  }

  if (Object.keys(patch).length === 0) return { ok: false, reason: 'no editable fields in body' };
  return { ok: true, patch };
}

/**
 * Handle any /voice-commands request. Returns false when the route didn't match,
 * so server.ts can fall through to the next handler.
 */
export async function handleVoiceCommands(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<boolean> {
  const url = (req.url ?? '').split('?')[0];
  if (!url.startsWith('/voice-commands')) return false;

  const auth = await authorizeRequest(req);
  if (!auth.ok) {
    json(res, auth.status, { ok: false, reason: auth.reason });
    return true;
  }

  const idMatch = url.match(/^\/voice-commands\/([^/]+)$/);
  const id = idMatch?.[1];

  try {
    if (url === '/voice-commands' && req.method === 'GET') {
      const { data, error } = await supabase
        .from(TABLE)
        .select('*')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: true });
      if (error) throw error;
      json(res, 200, { ok: true, commands: data ?? [] });
      return true;
    }

    if (url === '/voice-commands' && req.method === 'POST') {
      const parsed = voiceCommandInsert(JSON.parse((await readBody(req)) || '{}'));
      if (!parsed.ok) {
        json(res, 400, { ok: false, reason: parsed.reason });
        return true;
      }
      const { data, error } = await supabase.from(TABLE).insert(parsed.row).select().single();
      if (error) throw error;
      json(res, 201, { ok: true, command: data });
      return true;
    }

    if (id && req.method === 'PATCH') {
      const parsed = voiceCommandPatch(JSON.parse((await readBody(req)) || '{}'));
      if (!parsed.ok) {
        json(res, 400, { ok: false, reason: parsed.reason });
        return true;
      }
      const { data, error } = await supabase
        .from(TABLE)
        .update(parsed.patch)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      json(res, 200, { ok: true, command: data });
      return true;
    }

    if (id && req.method === 'DELETE') {
      const { error } = await supabase.from(TABLE).delete().eq('id', id);
      if (error) throw error;
      json(res, 200, { ok: true });
      return true;
    }

    json(res, 405, { ok: false, reason: 'method not allowed' });
    return true;
  } catch (e) {
    json(res, 500, { ok: false, reason: e instanceof Error ? e.message : String(e) });
    return true;
  }
}
