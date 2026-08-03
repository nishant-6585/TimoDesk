/**
 * POST /enroll — Staff face enrollment endpoint
 *
 * DPDP-compliant biometric enrollment:
 * - JWT auth (fail-closed: no anonymous writes)
 * - Consent gate (must explicitly consent)
 * - Face detection (exactly 1 face required)
 * - Embedding extraction (128-dim)
 * - Staff upsert + embedding storage
 * - Audit logging (who enrolled whom, under what consent)
 *
 * Reuses spine's existing JWT secret for auth consistency.
 */

import { IncomingMessage, ServerResponse } from 'http';
import { SupabaseClient } from '@supabase/supabase-js';
import { authorizeRequest } from '../auth/middleware';
import { logEvent } from '../supabase/events';
import { extractEmbedding } from '../services/face-embedding';
import { upsertStaffKb } from '../services/kb-staff';

export interface EnrollRequest {
  jwt?: string; // Deprecated: use Authorization header instead
  full_name: string;
  phone?: string;
  person_type?: string; // 'Employee' or 'Staff'
  role?: string;
  notify_channel?: string;
  consent: boolean;
  consent_ref: string;
  image_base64: string; // Base64-encoded JPEG/PNG
  set_thumbnail?: boolean; // True → use THIS photo as the gallery display thumbnail (the front-facing shot)
  desk_pose?: DeskPose; // Optional SLAM pose of the person's desk, captured during enrollment (#71)
}

/** A staff member's desk location — SLAM pose from getPosition(). */
export interface DeskPose {
  x: number;
  y: number;
  z?: number;
  rotation?: number;
}

/**
 * Map a desk pose to the staff table's desk_* columns, or null if the pose is
 * absent/invalid (x & y are required and must be finite). Shared by /enroll and
 * PATCH /staff so both write the pose identically.
 */
export function deskColumns(pose: DeskPose | undefined | null): Record<string, unknown> | null {
  if (!pose || !Number.isFinite(pose.x) || !Number.isFinite(pose.y)) return null;
  return {
    desk_x: pose.x,
    desk_y: pose.y,
    desk_z: Number.isFinite(pose.z) ? pose.z : 0,
    desk_rotation: Number.isFinite(pose.rotation) ? pose.rotation : 0,
    desk_captured_at: new Date().toISOString(),
  };
}

export interface EnrollResponse {
  ok: boolean;
  staff_id?: string;
  embeddingId?: string;
  facesFound?: number;
  reason?: string;
}

/**
 * Handle POST /enroll
 */
export async function handleEnroll(
  req: IncomingMessage,
  res: ServerResponse,
  supabase: SupabaseClient
): Promise<void> {
  // Only accept POST
  if (req.method !== 'POST') {
    res.writeHead(405);
    res.end(JSON.stringify({ ok: false, reason: 'Method not allowed' }));
    return;
  }

  try {
    // 1. AUTHORIZE (fail-closed)
    const authz = await authorizeRequest(req);
    if (!authz.ok) {
      res.writeHead(authz.status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, reason: authz.reason }));
      return;
    }

    const enrolledBy = authz.userId;

    // 2. PARSE REQUEST BODY
    let body = '';
    req.on('data', chunk => {
      body += chunk.toString();
    });

    req.on('end', async () => {
      try {
        const enrollReq: EnrollRequest = JSON.parse(body);

        // 3. DPDP CONSENT GATE
        if (!enrollReq.consent) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: 'Consent required for enrollment' }));
          return;
        }

        if (!enrollReq.consent_ref) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: 'consent_ref required' }));
          return;
        }

        // 4. DECODE IMAGE
        let imageBuffer: Buffer;
        try {
          imageBuffer = Buffer.from(enrollReq.image_base64, 'base64');
        } catch (err) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: 'Invalid base64 image' }));
          return;
        }

        // 5. EXTRACT EMBEDDING (require exactly 1 face)
        const embeddingResult = await extractEmbedding(imageBuffer);

        if (!embeddingResult.ok) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(
            JSON.stringify({
              ok: false,
              reason: embeddingResult.error,
              facesFound: embeddingResult.facesFound ?? 0,
            })
          );
          return;
        }

        const embedding = embeddingResult.embedding!;

        // 6. SELECT OR CREATE STAFF (UUID, not slug)
        // First: try to find existing staff by full_name
        let staffId: string;
        const { data: existingStaff, error: selectError } = await supabase
          .from('staff')
          .select('id')
          .eq('full_name', enrollReq.full_name)
          .maybeSingle();

        if (selectError && selectError.code !== 'PGRST116') {
          console.error(`[Enroll] Staff select failed: ${selectError.message}`);
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: 'Failed to check staff' }));
          return;
        }

        if (existingStaff) {
          // Reuse existing staff UUID, optionally update phone/person_type
          staffId = existingStaff.id;

          // Update phone and person_type if provided
          if (enrollReq.phone || enrollReq.person_type) {
            const updateData: any = {};
            if (enrollReq.phone) updateData.phone = enrollReq.phone;
            if (enrollReq.person_type) updateData.person_type = enrollReq.person_type;

            await supabase
              .from('staff')
              .update(updateData)
              .eq('id', staffId);
          }

          console.log(`[Enroll] Found existing staff: ${staffId}`);
        } else {
          // Create new staff (id will be auto-generated UUID)
          const { data: newStaff, error: insertError } = await supabase
            .from('staff')
            .insert({
              full_name: enrollReq.full_name,
              phone: enrollReq.phone,
              person_type: enrollReq.person_type || 'Employee',
              role: enrollReq.role,
              notify_channel: enrollReq.notify_channel,
              active: true,
            })
            .select('id')
            .single();

          if (insertError || !newStaff) {
            console.error(`[Enroll] Staff creation failed: ${insertError?.message}`);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: false, reason: 'Failed to create staff record' }));
            return;
          }

          staffId = newStaff.id;
          console.log(`[Enroll] Created new staff: ${staffId}`);
        }

        // 6b. DESK POSE (optional) — record where this person sits, captured during
        // enrollment. Written whenever provided (create or repeat pose call).
        const desk = deskColumns(enrollReq.desk_pose);
        if (desk) {
          const { error: deskErr } = await supabase.from('staff').update(desk).eq('id', staffId);
          if (deskErr) console.warn(`[Enroll] desk pose update failed (continuing): ${deskErr.message}`);
          else console.log(`[Enroll] desk pose saved for ${staffId}`);
        }

        // 7. INSERT EMBEDDING (pgvector: pass as string array)
        const embeddingString = '[' + embedding.join(',') + ']';
        const { data: embeddingData, error: embedError } = await supabase
          .from('staff_face_embedding')
          .insert({
            staff_id: staffId,
            embedding: embeddingString,
            consent_at: new Date().toISOString(),
            consent_ref: enrollReq.consent_ref,
          })
          .select('id')
          .single();

        if (embedError) {
          console.error(`[Enroll] Embedding insert failed: ${embedError.message}`);
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, reason: 'Failed to store embedding' }));
          return;
        }

        const embeddingId = embeddingData?.id;

        // 7b. UPLOAD DISPLAY THUMBNAIL (best-effort — never fail enrollment on this).
        // Only the FRONT-facing photo is kept as the gallery image: the client sets
        // set_thumbnail=true for that shot (single web capture, or pose 0 on the robot).
        // Other poses skip this so a side/down pose never overwrites the front face.
        // UI-only cropped JPEG; the embedding above is the record that matters.
        if (embeddingResult.thumbnail && enrollReq.set_thumbnail === true) {
          try {
            const photoPath = `${staffId}.jpg`;
            const { error: uploadErr } = await supabase.storage
              .from('staff-photos')
              .upload(photoPath, embeddingResult.thumbnail, {
                contentType: 'image/jpeg',
                upsert: true,
              });
            if (uploadErr) {
              console.warn(`[Enroll] Thumbnail upload failed (continuing): ${uploadErr.message}`);
            } else {
              await supabase.from('staff').update({ photo_path: photoPath }).eq('id', staffId);
            }
          } catch (err) {
            console.warn(
              `[Enroll] Thumbnail step errored (continuing): ${err instanceof Error ? err.message : String(err)}`
            );
          }
        }

        // 8. AUDIT LOG (DPDP: record who enrolled whom, under what consent)
        await logEvent('staff_enrolled', {
          actor: enrolledBy,
          staff_id: staffId,
          full_name: enrollReq.full_name,
          embeddingId,
          consent_ref: enrollReq.consent_ref,
        });

        console.log(
          `[Enroll] ✅ ${enrollReq.full_name} enrolled by ${enrolledBy} (embedding: ${embeddingId})`
        );

        // 8b. KB SYNC (best-effort, non-blocking) — keep this person answerable
        // by the voice brain ("who is X", "X's number", "where does X sit"). Never
        // fail or delay enrollment on this; Voyage may rate-limit.
        upsertStaffKb(supabase, staffId).catch(e =>
          console.warn(
            `[Enroll] KB staff sync failed (continuing): ${e instanceof Error ? e.message : String(e)}`
          )
        );

        // 9. RETURN SUCCESS
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(
          JSON.stringify({
            ok: true,
            staff_id: staffId,
            embeddingId,
          })
        );
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        console.error(`[Enroll] Error: ${message}`);
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, reason: message }));
      }
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[Enroll] Fatal error: ${message}`);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: false, reason: 'Internal error' }));
  }
}
