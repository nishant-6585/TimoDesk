/**
 * kb-staff.ts — sync enrolled staff (name, role/designation, phone, desk
 * location) into the KB so the voice brain can answer "who is David?",
 * "what's Saravan's number?", "where does Srishti sit?".
 *
 * Each staff row becomes ONE kb_chunk tagged `source='staff:<id>'` so a re-sync
 * (or a single-staff update on enrollment) can delete + re-insert cleanly
 * without duplicating. staffToKbText is a pure function (unit-tested); the sync
 * orchestrators do the Supabase + Voyage I/O.
 *
 * PRIVACY: phone numbers land in a KB the agent can read aloud. Gate phone in
 * the ElevenLabs system prompt (e.g. only reveal to a recognised staff member)
 * if visitors should not hear it. Content here is DPDP-relevant — staff only,
 * who enrolled with consent; the `visitor` table is never synced.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { ingestText, IngestDeps } from './kb-ingest';

/** The staff columns this module reads. Kept minimal + explicit. */
export interface StaffKbRow {
  id: string;
  full_name: string;
  role?: string | null;
  person_type?: string | null;
  phone?: string | null;
  desk_x?: number | null;
  desk_y?: number | null;
}

const STAFF_SELECT = 'id, full_name, role, person_type, phone, desk_x, desk_y';
/** Anything with this source prefix is staff-derived and owned by this module. */
export const STAFF_SOURCE_PREFIX = 'staff:';

/**
 * Render one staff row as a natural, self-contained KB chunk. Pure — no I/O.
 * Written so common phrasings ("David's number", "what does David do", "where
 * does David sit") all retrieve the same chunk.
 */
export function staffToKbText(s: StaffKbRow): string {
  const name = (s.full_name || '').trim();
  const role = (s.role || '').trim();
  const type = (s.person_type || '').trim();
  const phone = (s.phone || '').trim();
  const hasDesk = Number.isFinite(s.desk_x) && Number.isFinite(s.desk_y);

  const sentences: string[] = [];
  if (role) {
    sentences.push(
      `${name} is part of the xboom team${type ? ` (${type})` : ''}; their role is ${role}.`
    );
  } else {
    sentences.push(`${name} is part of the xboom team${type ? ` (${type})` : ''}.`);
  }
  if (phone) sentences.push(`${name}'s phone number is ${phone}.`);
  if (hasDesk) {
    sentences.push(
      `${name} has a saved desk location — you can ask me to take you to ${name}'s desk and I will guide you there.`
    );
  }
  return `Staff directory entry for ${name}. ${sentences.join(' ')}`;
}

/** Delete every staff-derived chunk (used before a full re-sync). */
async function deleteAllStaffChunks(supabase: SupabaseClient): Promise<void> {
  const { error } = await supabase
    .from('kb_chunk')
    .delete()
    .like('source', `${STAFF_SOURCE_PREFIX}%`);
  if (error) throw new Error(`kb staff cleanup failed: ${error.message}`);
}

/** Ingest one already-fetched staff row (delete its old chunk first). */
async function ingestOne(
  supabase: SupabaseClient,
  s: StaffKbRow,
  deps: IngestDeps
): Promise<number> {
  if (!s.full_name || !s.full_name.trim()) return 0;
  const { chunks } = await ingestText(
    supabase,
    {
      text: staffToKbText(s),
      topic: `Staff: ${s.full_name.trim()}`,
      is_faq: false,
      source: `${STAFF_SOURCE_PREFIX}${s.id}`,
    },
    deps
  );
  return chunks;
}

/**
 * Full re-sync: replace all staff-derived KB chunks with the current active
 * staff. Sequential (Voyage free tier is rate-limited) with a small retry on
 * transient embed failures. Returns counts for the caller to report.
 */
export async function syncStaffToKb(
  supabase: SupabaseClient,
  deps: IngestDeps = {}
): Promise<{ staff: number; chunks: number }> {
  await deleteAllStaffChunks(supabase);

  const { data, error } = await supabase
    .from('staff')
    .select(STAFF_SELECT)
    .eq('active', true);
  if (error) throw new Error(`staff fetch failed: ${error.message}`);

  const rows = (data ?? []) as StaffKbRow[];
  let chunks = 0;
  for (const s of rows) {
    chunks += await withRetry(() => ingestOne(supabase, s, deps));
  }
  return { staff: rows.length, chunks };
}

/**
 * Upsert a SINGLE staff member's KB chunk (delete their old chunk, re-add).
 * Called after enrollment/update so the KB stays current without a full,
 * rate-limited re-embed of everyone. Best-effort: throws so the caller can log,
 * but the caller should treat it as non-fatal to the enrollment itself.
 */
export async function upsertStaffKb(
  supabase: SupabaseClient,
  staffId: string,
  deps: IngestDeps = {}
): Promise<void> {
  const { error: delErr } = await supabase
    .from('kb_chunk')
    .delete()
    .eq('source', `${STAFF_SOURCE_PREFIX}${staffId}`);
  if (delErr) throw new Error(`kb staff delete failed: ${delErr.message}`);

  const { data, error } = await supabase
    .from('staff')
    .select(STAFF_SELECT)
    .eq('id', staffId)
    .eq('active', true)
    .maybeSingle();
  if (error) throw new Error(`staff fetch failed: ${error.message}`);
  if (!data) return; // inactive/deleted → leave it removed
  await withRetry(() => ingestOne(supabase, data as StaffKbRow, deps));
}

/** Retry a Voyage-backed ingest twice on rate-limit/transient errors. */
async function withRetry<T>(fn: () => Promise<T>): Promise<T> {
  const delays = [0, 21_000, 21_000]; // free tier: 3 req/min → ~20s spacing
  let lastErr: unknown;
  for (const delay of delays) {
    if (delay) await new Promise(r => setTimeout(r, delay));
    try {
      return await fn();
    } catch (err) {
      lastErr = err;
      const msg = err instanceof Error ? err.message : String(err);
      if (!/429|rate|timeout|ETIMEDOUT|ECONN/i.test(msg)) throw err; // non-transient
    }
  }
  throw lastErr;
}
