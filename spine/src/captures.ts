/**
 * captures.ts — admin remote-snapshot persistence (F7).
 *
 * Two pure-ish helpers around Supabase Storage + the `capture` table, kept out of
 * the WS/HTTP handlers so they can be unit-tested with a fake Supabase client:
 *
 *   saveSnapshot()  — upload a JPEG buffer + insert a `capture` row (admin_snapshot)
 *   listSnapshots() — read recent admin snapshots + mint short-lived signed URLs
 *
 * The `capture` retention trigger (migration 005) auto-sets purge_after (30d), so
 * we never set it here. The `snapshots` bucket + `capture.actor` come from
 * migration 012.
 */

import { SupabaseClient } from '@supabase/supabase-js';

/** Private Storage bucket for admin snapshots (migration 012). */
export const SNAPSHOTS_BUCKET = 'snapshots';

/** Signed-URL lifetime for gallery thumbnails — short, since the Gallery re-fetches. */
export const SNAPSHOT_URL_TTL_SECONDS = 60 * 60; // 1 hour

export interface SavedSnapshot {
  captureId: string;
  path: string;
}

export interface SnapshotListItem {
  id: string;
  taken_at: string;
  actor: string | null;
  image_url: string | null;
}

/**
 * Persist a snapshot: upload the JPEG to the `snapshots` bucket, then record a
 * `capture` row (kind=admin_snapshot). Throws on upload or insert failure so the
 * caller can surface an error to the operator (the shot was taken but not saved).
 *
 * @param supabase service-role client (bypasses RLS for upload + insert)
 * @param buffer   JPEG bytes from the robot camera
 * @param actor    who triggered it (auth user id / 'kiosk-robot'); null if unknown
 * @param now      injectable clock for a deterministic object path (defaults to Date.now)
 */
export async function saveSnapshot(
  supabase: SupabaseClient,
  buffer: Buffer,
  actor: string | null,
  now: () => number = Date.now
): Promise<SavedSnapshot> {
  // Unique, sortable object path. No PII in the name.
  const path = `admin/${now()}.jpg`;

  const { error: uploadErr } = await supabase.storage
    .from(SNAPSHOTS_BUCKET)
    .upload(path, buffer, { contentType: 'image/jpeg', upsert: false });
  if (uploadErr) {
    throw new Error(`snapshot upload failed: ${uploadErr.message}`);
  }

  const { data, error: insertErr } = await supabase
    .from('capture')
    .insert({ kind: 'admin_snapshot', storage_url: path, actor })
    .select('id')
    .single();
  if (insertErr) {
    throw new Error(`capture insert failed: ${insertErr.message}`);
  }

  return { captureId: data.id as string, path };
}

/**
 * List recent admin snapshots (newest first) with short-lived signed image URLs.
 * A row whose signed URL fails to mint (deleted object, etc.) gets image_url=null
 * so the Gallery can render a graceful placeholder instead of breaking.
 */
export async function listSnapshots(
  supabase: SupabaseClient,
  limit = 100
): Promise<SnapshotListItem[]> {
  const { data: rows, error } = await supabase
    .from('capture')
    .select('id, storage_url, actor, taken_at')
    .eq('kind', 'admin_snapshot')
    .order('taken_at', { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);

  const captures = rows ?? [];
  const paths = captures
    .map(c => (c as { storage_url?: string }).storage_url)
    .filter((p): p is string => !!p);

  const signedByPath: Record<string, string> = {};
  if (paths.length) {
    const { data: signed } = await supabase.storage
      .from(SNAPSHOTS_BUCKET)
      .createSignedUrls(paths, SNAPSHOT_URL_TTL_SECONDS);
    for (const s of signed ?? []) {
      if (s.path && s.signedUrl && !s.error) signedByPath[s.path] = s.signedUrl;
    }
  }

  return captures.map(c => {
    const row = c as { id: string; storage_url?: string; actor?: string | null; taken_at: string };
    return {
      id: row.id,
      taken_at: row.taken_at,
      actor: row.actor ?? null,
      image_url: row.storage_url ? signedByPath[row.storage_url] ?? null : null,
    };
  });
}
