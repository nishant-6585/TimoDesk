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
/** True when a Postgres/PostgREST error is about the missing capture.actor
 *  column (migration 012 not applied). Covers both the raw "column ... does
 *  not exist" and PostgREST's "Could not find the 'actor' column ... in the
 *  schema cache" phrasings. */
function isActorMissing(msg: string): boolean {
  return /actor/i.test(msg) &&
    /(does not exist|schema cache|could not find)/i.test(msg);
}

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

  const base = { kind: 'admin_snapshot', storage_url: path };
  let ins = await supabase.from('capture').insert({ ...base, actor }).select('id').single();
  // Forward-compatible: if migration 012 (capture.actor) hasn't been applied
  // yet, store the snapshot WITHOUT attribution rather than failing outright.
  if (ins.error && isActorMissing(ins.error.message)) {
    console.warn('[captures] capture.actor missing — storing snapshot without attribution (apply migration 012)');
    ins = await supabase.from('capture').insert(base).select('id').single();
  }
  if (ins.error) {
    throw new Error(`capture insert failed: ${ins.error.message}`);
  }

  return { captureId: ins.data!.id as string, path };
}

/**
 * Persist a visitor ARRIVAL snapshot (F1). Distinct from saveSnapshot(): this
 * one is attached to a `visitor` row, not the admin gallery.
 *
 * DPDP: this is the one visitor image the blueprint permits — a plain arrival
 * photo on the visitor record. It is NEVER run through face embedding and never
 * reaches `staff_face_embedding`; visitors are detected, never enrolled. The
 * row's own `purge_after` (30d) governs it, and deleting the storage object is
 * part of the purge story below.
 *
 * Best-effort by contract: returns null instead of throwing, because a visitor
 * standing at reception must be checked in and their host notified even if
 * Storage is unavailable. The caller logs the miss.
 */
export async function saveVisitorArrivalSnapshot(
  supabase: SupabaseClient,
  buffer: Buffer,
  visitorId: string,
  now: () => number = Date.now
): Promise<string | null> {
  // Path carries the visitor id (already an opaque uuid) — no name, no PII.
  const path = `visitor/${visitorId}/${now()}.jpg`;
  try {
    const { error: uploadErr } = await supabase.storage
      .from(SNAPSHOTS_BUCKET)
      .upload(path, buffer, { contentType: 'image/jpeg', upsert: false });
    if (uploadErr) {
      console.warn(`[captures] arrival snapshot upload failed: ${uploadErr.message}`);
      return null;
    }
    const { error: updErr } = await supabase
      .from('visitor')
      .update({ snapshot_url: path })
      .eq('id', visitorId);
    if (updErr) {
      console.warn(`[captures] arrival snapshot link failed: ${updErr.message}`);
      return null;
    }
    return path;
  } catch (err) {
    console.warn('[captures] arrival snapshot failed:', err instanceof Error ? err.message : String(err));
    return null;
  }
}

/**
 * Persist an intrusion frame (F9). Same bucket, different `capture.kind` —
 * migration 005's retention trigger gives 'intrusion' a 365-day window (vs 30
 * days for everything else), which is why the kind string matters here.
 *
 * Best-effort like the arrival snapshot: an alarm must still sound and alert
 * even if Storage is down. Returns the capture id when stored, else null.
 */
export async function saveIntrusionCapture(
  supabase: SupabaseClient,
  buffer: Buffer,
  now: () => number = Date.now
): Promise<{ captureId: string; path: string } | null> {
  const path = `intrusion/${now()}.jpg`;
  try {
    const { error: uploadErr } = await supabase.storage
      .from(SNAPSHOTS_BUCKET)
      .upload(path, buffer, { contentType: 'image/jpeg', upsert: false });
    if (uploadErr) {
      console.warn(`[captures] intrusion upload failed: ${uploadErr.message}`);
      return null;
    }
    const base = { kind: 'intrusion', storage_url: path };
    let ins = await supabase.from('capture').insert({ ...base, actor: 'security' }).select('id').single();
    if (ins.error && isActorMissing(ins.error.message)) {
      ins = await supabase.from('capture').insert(base).select('id').single();
    }
    if (ins.error) {
      console.warn(`[captures] intrusion insert failed: ${ins.error.message}`);
      return null;
    }
    return { captureId: ins.data!.id as string, path };
  } catch (err) {
    console.warn('[captures] intrusion capture failed:', err instanceof Error ? err.message : String(err));
    return null;
  }
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
  const withActor = await supabase
    .from('capture')
    .select('id, storage_url, actor, taken_at')
    .eq('kind', 'admin_snapshot')
    .order('taken_at', { ascending: false })
    .limit(limit);
  // Same forward-compat as saveSnapshot: fall back to no-actor if the column
  // isn't there yet, so the Gallery still lists snapshots.
  let rows: unknown[] | null = withActor.data;
  let error = withActor.error;
  if (error && isActorMissing(error.message)) {
    const noActor = await supabase
      .from('capture')
      .select('id, storage_url, taken_at')
      .eq('kind', 'admin_snapshot')
      .order('taken_at', { ascending: false })
      .limit(limit);
    rows = noActor.data;
    error = noActor.error;
  }
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

/** Delete a snapshot: remove the storage object then the capture row. */
export async function deleteSnapshot(
  supabase: SupabaseClient,
  id: string
): Promise<void> {
  const { data: row, error: selErr } = await supabase
    .from('capture')
    .select('storage_url')
    .eq('id', id)
    .single();
  if (selErr) throw new Error(selErr.message);
  const storagePath = (row as { storage_url?: string })?.storage_url;
  if (storagePath) {
    await supabase.storage.from(SNAPSHOTS_BUCKET).remove([storagePath]);
  }
  const { error: delErr } = await supabase.from('capture').delete().eq('id', id);
  if (delErr) throw new Error(delErr.message);
}
