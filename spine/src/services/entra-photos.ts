/**
 * entra-photos.ts — Entra ID directory photo → face-embedding import.
 *
 * For every ACTIVE synced staff row (entra_id set), fetch the Graph profile
 * photo and turn it into a `staff_face_embedding` row via the SHARED
 * extractEmbedding pipeline (same model/preprocessing as on-robot enrollment,
 * or matching breaks). The result is bootstrap enrollment: employees with a
 * usable directory photo are recognizable without ever standing in front of
 * the robot; the admin Staff screen shows who needs a 5-pose top-up.
 *
 * Guard rails (enrollment quality is the #1 recognition problem — see
 * docs/ENTRA_ID_INTEGRATION_PLAN.md §Phase 1):
 *
 *   • CONSENT: when a consented-id set is passed (the ENTRA_CONSENT_GROUP_ID
 *     security group), non-members never have biometrics computed; leaving the
 *     group deletes previously imported embeddings (audit-logged).
 *   • ETag skip: unchanged photos are never re-downloaded or re-embedded.
 *   • Quality gates: exactly one face (shared extractor), face box at least
 *     ENTRA_MIN_FACE_PX (default 120 px — a 96×96 AD thumbnailPhoto fails).
 *   • Collision gate: an embedding landing within threshold+margin of a
 *     DIFFERENT person is rejected (status 'collision') instead of stored —
 *     it would only create misrecognitions.
 *
 * Embeddings carry consent_ref 'entra-photo:<ref>' so consent-revocation and
 * offboarding purges can target exactly the directory-sourced rows. A photo
 * change replaces the previous entra-photo rows; on-robot poses are untouched.
 *
 * Injectable fetch/embed so tests run without Graph or the face-api models
 * (face-embedding.ts is imported lazily — it drags in canvas/tfjs natives).
 */

import crypto from 'crypto';
import { SupabaseClient } from '@supabase/supabase-js';
import { FACE_CONFIG } from '../config/face-recognition';
import { logEvent } from '../supabase/events';

/** Structural mirror of FaceEmbeddingResult (no static face-api import). */
export interface EmbedResultLike {
  ok: boolean;
  embedding?: number[];
  facesFound?: number;
  error?: string;
  thumbnail?: Buffer;
  faceBox?: { x: number; y: number; width: number; height: number };
}

export interface EntraPhotoDeps {
  fetchImpl?: typeof fetch;
  embedImpl?: (image: Buffer) => Promise<EmbedResultLike>;
  logEventImpl?: typeof logEvent;
}

export interface EntraPhotoSummary {
  considered: number;
  embedded: number;
  skipped_unchanged: number;
  no_photo: number;
  no_consent: number;
  rejected_quality: number;
  rejected_multi_face: number;
  collisions: number;
  errors: number;
  revoked: number; // staff whose embeddings were deleted on consent withdrawal
}

const GRAPH_BASE = 'https://graph.microsoft.com/v1.0';
const ENTRA_CONSENT_PREFIX = 'entra-photo:';

/** Statuses where a matching etag means "nothing to redo". Collisions retry
 *  every sync — they depend on OTHER people's embeddings, which change. */
const ETAG_SKIP_STATUSES = new Set(['ok', 'rejected_quality', 'rejected_multi_face']);

function minFacePx(): number {
  const n = Number(process.env.ENTRA_MIN_FACE_PX ?? '120');
  return Number.isFinite(n) && n > 0 ? n : 120;
}

interface PhotoStaffRow {
  id: string;
  full_name: string;
  active: boolean;
  entra_id: string | null;
  photo_path: string | null;
  entra_photo_etag: string | null;
  entra_photo_status: string | null;
}

interface KnownEmbedding {
  staffId: string;
  vec: number[];
  isEntra: boolean;
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

function l2(a: number[], b: number[]): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    const d = a[i] - b[i];
    s += d * d;
  }
  return Math.sqrt(s);
}

/** Photo metadata; etag null when Graph sends none (change detection then falls back to a content hash). */
async function getPhotoEtag(
  f: typeof fetch,
  token: string,
  entraId: string
): Promise<{ exists: boolean; etag: string | null }> {
  const resp = await f(`${GRAPH_BASE}/users/${entraId}/photo`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (resp.status === 404) return { exists: false, etag: null };
  if (!resp.ok) {
    const detail = await resp.text().catch(() => '');
    throw new Error(`Graph photo meta failed: ${resp.status} ${detail}`.trim());
  }
  const meta = (await resp.json()) as { '@odata.mediaEtag'?: string };
  return { exists: true, etag: meta['@odata.mediaEtag'] ?? null };
}

/** Photo binary — largest available; null when the user has none (404). */
async function fetchPhotoBytes(
  f: typeof fetch,
  token: string,
  entraId: string
): Promise<Buffer | null> {
  const resp = await f(`${GRAPH_BASE}/users/${entraId}/photo/$value`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (resp.status === 404) return null;
  if (!resp.ok) {
    const detail = await resp.text().catch(() => '');
    throw new Error(`Graph photo fetch failed: ${resp.status} ${detail}`.trim());
  }
  return Buffer.from(await resp.arrayBuffer());
}

async function deleteEntraEmbeddings(supabase: SupabaseClient, staffId: string): Promise<void> {
  const { error } = await supabase
    .from('staff_face_embedding')
    .delete()
    .eq('staff_id', staffId)
    .like('consent_ref', `${ENTRA_CONSENT_PREFIX}%`);
  if (error) throw new Error(`entra embedding delete failed: ${error.message}`);
}

/**
 * Run the photo pass over all active synced staff.
 *
 * `consentedIds` — Graph user ids of the consent group (null = mode 'all':
 * every synced employee is treated as consented; the caller asserts the
 * lawful basis, see runEntraSync).
 */
export async function syncEntraPhotos(
  supabase: SupabaseClient,
  token: string,
  consentedIds: Set<string> | null,
  deps: EntraPhotoDeps = {}
): Promise<EntraPhotoSummary> {
  const f = deps.fetchImpl ?? fetch;
  const logEventImpl = deps.logEventImpl ?? logEvent;
  const embedImpl =
    deps.embedImpl ??
    (async (image: Buffer) => (await import('./face-embedding')).extractEmbedding(image));

  const summary: EntraPhotoSummary = {
    considered: 0,
    embedded: 0,
    skipped_unchanged: 0,
    no_photo: 0,
    no_consent: 0,
    rejected_quality: 0,
    rejected_multi_face: 0,
    collisions: 0,
    errors: 0,
    revoked: 0,
  };

  const { data: staffRows, error: staffErr } = await supabase
    .from('staff')
    .select('id, full_name, active, entra_id, photo_path, entra_photo_etag, entra_photo_status');
  if (staffErr) throw new Error(`staff load failed: ${staffErr.message}`);
  const staff = ((staffRows ?? []) as PhotoStaffRow[]).filter(s => s.entra_id && s.active);

  const { data: embRows, error: embErr } = await supabase
    .from('staff_face_embedding')
    .select('staff_id, embedding, consent_ref');
  if (embErr) throw new Error(`embedding load failed: ${embErr.message}`);
  const known: KnownEmbedding[] = [];
  for (const r of embRows ?? []) {
    const vec = parseEmbedding((r as { embedding: unknown }).embedding);
    if (!vec || vec.length !== FACE_CONFIG.embedding_dim) continue;
    known.push({
      staffId: (r as { staff_id: string }).staff_id,
      vec,
      isEntra: String((r as { consent_ref?: string }).consent_ref ?? '').startsWith(ENTRA_CONSENT_PREFIX),
    });
  }
  const hasEntraEmbedding = new Set(known.filter(k => k.isEntra).map(k => k.staffId));

  const collisionCutoff = FACE_CONFIG.threshold + FACE_CONFIG.match_margin;
  const nowIso = () => new Date().toISOString();

  const setStatus = async (s: PhotoStaffRow, patch: Record<string, unknown>) => {
    const { error } = await supabase
      .from('staff')
      .update({ ...patch, entra_synced_at: nowIso() })
      .eq('id', s.id);
    if (error) console.warn(`[Entra] photo status update failed for ${s.full_name}: ${error.message}`);
  };

  for (const s of staff) {
    summary.considered++;
    try {
      // 1. Consent gate — never compute biometrics for non-consented users,
      //    and erase what an earlier consent allowed.
      const consented = consentedIds === null || consentedIds.has(s.entra_id as string);
      if (!consented) {
        summary.no_consent++;
        if (hasEntraEmbedding.has(s.id)) {
          await deleteEntraEmbeddings(supabase, s.id);
          hasEntraEmbedding.delete(s.id);
          for (let i = known.length - 1; i >= 0; i--) {
            if (known[i].staffId === s.id && known[i].isEntra) known.splice(i, 1);
          }
          summary.revoked++;
          await logEventImpl('entra_consent_revoked', {
            staff_id: s.id,
            full_name: s.full_name,
          });
          await setStatus(s, { entra_photo_status: 'no_consent', entra_photo_etag: null });
        } else if (s.entra_photo_status !== 'no_consent') {
          await setStatus(s, { entra_photo_status: 'no_consent' });
        }
        continue;
      }

      // 2. Photo metadata / change detection.
      const meta = await getPhotoEtag(f, token, s.entra_id as string);
      if (!meta.exists) {
        summary.no_photo++;
        // A vanished photo is not a consent withdrawal — existing embeddings stay.
        if (!hasEntraEmbedding.has(s.id) && s.entra_photo_status !== 'none') {
          await setStatus(s, { entra_photo_status: 'none' });
        }
        continue;
      }
      if (
        meta.etag &&
        meta.etag === s.entra_photo_etag &&
        ETAG_SKIP_STATUSES.has(s.entra_photo_status ?? '')
      ) {
        summary.skipped_unchanged++;
        continue;
      }

      // 3. Download + embed through the shared pipeline.
      const bytes = await fetchPhotoBytes(f, token, s.entra_id as string);
      if (!bytes) {
        summary.no_photo++;
        continue;
      }
      const photoRef = meta.etag ?? `sha1:${crypto.createHash('sha1').update(bytes).digest('hex')}`;
      if (
        !meta.etag &&
        s.entra_photo_etag === photoRef &&
        ETAG_SKIP_STATUSES.has(s.entra_photo_status ?? '')
      ) {
        summary.skipped_unchanged++;
        continue;
      }

      const emb = await embedImpl(bytes);
      if (!emb.ok || !emb.embedding) {
        if ((emb.facesFound ?? 0) > 1) {
          summary.rejected_multi_face++;
          await setStatus(s, { entra_photo_status: 'rejected_multi_face', entra_photo_etag: photoRef });
        } else if (emb.facesFound === 0) {
          summary.rejected_quality++;
          await setStatus(s, { entra_photo_status: 'rejected_quality', entra_photo_etag: photoRef });
        } else {
          summary.errors++;
          await setStatus(s, { entra_photo_status: 'error' });
        }
        continue;
      }

      // 4. Quality gate: tiny faces make junk embeddings.
      const box = emb.faceBox;
      if (box && Math.min(box.width, box.height) < minFacePx()) {
        summary.rejected_quality++;
        await setStatus(s, { entra_photo_status: 'rejected_quality', entra_photo_etag: photoRef });
        continue;
      }

      // 5. Collision gate: nearest OTHER person must not be within match range.
      let nearestOther = Infinity;
      let nearestOtherStaff = '';
      for (const k of known) {
        if (k.staffId === s.id) continue;
        const d = l2(emb.embedding, k.vec);
        if (d < nearestOther) {
          nearestOther = d;
          nearestOtherStaff = k.staffId;
        }
      }
      if (nearestOther < collisionCutoff) {
        summary.collisions++;
        console.warn(
          `[Entra] photo for ${s.full_name} collides with staff ${nearestOtherStaff} ` +
            `(L2 ${nearestOther.toFixed(3)} < ${collisionCutoff}) — not stored`
        );
        await setStatus(s, { entra_photo_status: 'collision', entra_photo_etag: photoRef });
        continue;
      }

      // 6. Store: replace any previous directory-photo embedding for this staff.
      if (hasEntraEmbedding.has(s.id)) {
        await deleteEntraEmbeddings(supabase, s.id);
        for (let i = known.length - 1; i >= 0; i--) {
          if (known[i].staffId === s.id && known[i].isEntra) known.splice(i, 1);
        }
      }
      const { error: insErr } = await supabase.from('staff_face_embedding').insert({
        staff_id: s.id,
        embedding: '[' + emb.embedding.join(',') + ']',
        consent_at: nowIso(),
        consent_ref: `${ENTRA_CONSENT_PREFIX}${photoRef}`,
      });
      if (insErr) throw new Error(`embedding insert failed: ${insErr.message}`);
      known.push({ staffId: s.id, vec: emb.embedding, isEntra: true });
      hasEntraEmbedding.add(s.id);

      // Display thumbnail: only fill a blank — never clobber an on-robot photo.
      if (!s.photo_path && emb.thumbnail) {
        const photoPath = `${s.id}.jpg`;
        const { error: upErr } = await supabase.storage
          .from('staff-photos')
          .upload(photoPath, emb.thumbnail, { contentType: 'image/jpeg', upsert: true });
        if (upErr) console.warn(`[Entra] thumbnail upload failed for ${s.full_name}: ${upErr.message}`);
        else await supabase.from('staff').update({ photo_path: photoPath }).eq('id', s.id);
      }

      await setStatus(s, { entra_photo_status: 'ok', entra_photo_etag: photoRef });
      summary.embedded++;
      await logEventImpl('entra_photo_embedded', {
        staff_id: s.id,
        full_name: s.full_name,
        photo_ref: photoRef,
      });
    } catch (err) {
      summary.errors++;
      const reason = err instanceof Error ? err.message : String(err);
      console.warn(`[Entra] photo sync failed for ${s.full_name}: ${reason}`);
      await setStatus(s, { entra_photo_status: 'error' }).catch(() => {});
    }
  }

  return summary;
}
