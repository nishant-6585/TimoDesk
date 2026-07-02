/**
 * Face Recognition Service — autonomous spine-side recognizer.
 *
 * Loop (no browser): every ~0.5s grab a clean JPEG from the robot's /snapshot
 * endpoint → run the SHARED extractEmbedding (the exact face-api path enrollment
 * uses) → find the NEAREST enrolled embedding by L2 → if nearest < threshold
 * (FACE_CONFIG.threshold, calibrated 0.53 — precision-biased) emit
 * face_detected{staff} else face_detected{unknown}.
 *
 * Matching MUST mirror calibration: nearest-neighbour, NOT averaged / all-pairwise.
 * One face-api pipeline only (services/face-embedding.ts) — no divergent path.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { RobotEvent } from '../types';
import { extractEmbedding } from './face-embedding';
import { FACE_CONFIG } from '../config/face-recognition';

interface EnrolledEmbedding {
  staff_id: string;
  full_name: string;
  embedding: number[];
}

export interface MatchResult {
  matched: boolean;
  staff_id?: string;
  name: string; // staff name, or 'unknown'
  distance: number; // L2 to nearest enrolled embedding (Infinity if none)
}

function l2Distance(a: number[], b: number[]): number {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const d = a[i] - b[i];
    sum += d * d;
  }
  return Math.sqrt(sum);
}

// pgvector returns the embedding column as a string '[1,2,...]'; parse to number[].
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

export class FaceRecognitionService {
  private readonly robotIP: string;
  private readonly cameraPort = FACE_CONFIG.camera_port; // 8080
  private readonly threshold = FACE_CONFIG.threshold; // 0.53, calibrated (precision-biased)
  private readonly margin = FACE_CONFIG.match_margin; // 0.06 second-place gap
  private readonly voteWindow = FACE_CONFIG.vote_window; // last N frames (3)
  private readonly voteMin = FACE_CONFIG.vote_min; // need this many agreeing (2)
  private readonly cadenceMs = FACE_CONFIG.detection_cadence_ms; // 500
  private readonly reloadMs = 30_000; // refresh enrolled set so new staff are picked up
  private readonly reEmitMs = 5_000; // re-confirm the same identity at most this often

  private supabase: SupabaseClient;
  private emit: (event: RobotEvent) => void;

  private enrolled: EnrolledEmbedding[] = [];
  private isRunning = false;
  private lastReload = 0;
  private lastEmitKey = '';
  private lastEmitAt = 0;
  private votes: MatchResult[] = []; // sliding window of recent per-frame results
  private noFaceStreak = 0; // consecutive frames with no single face

  constructor(robotIP: string, supabase: SupabaseClient, emit: (event: RobotEvent) => void) {
    this.robotIP = robotIP;
    this.supabase = supabase;
    this.emit = emit;
  }

  async start(): Promise<void> {
    console.log('[FaceRecognition] Starting autonomous recognizer…');
    await this.loadEnrolled();
    this.isRunning = true;
    console.log(
      `[FaceRecognition] ✅ Running — ${this.enrolled.length} enrolled embeddings, ` +
        `threshold ${this.threshold}, cadence ${this.cadenceMs}ms, source http://${this.robotIP}:${this.cameraPort}/snapshot`
    );
    this.loop(); // fire and forget; guarded internally
  }

  stop(): void {
    this.isRunning = false;
    console.log('[FaceRecognition] Stopped');
  }

  /** Load + flatten enrolled embeddings (parsed) with staff names. */
  private async loadEnrolled(): Promise<void> {
    const { data: rows, error } = await this.supabase
      .from('staff_face_embedding')
      .select('staff_id, embedding, staff:staff_id(full_name)');
    if (error) {
      console.error(`[FaceRecognition] load embeddings failed: ${error.message}`);
      return;
    }
    const flat: EnrolledEmbedding[] = [];
    for (const r of rows ?? []) {
      const emb = parseEmbedding((r as any).embedding);
      if (!emb || emb.length !== 128) continue;
      const name = (r as any).staff?.full_name ?? '(unknown staff)';
      flat.push({ staff_id: (r as any).staff_id, full_name: name, embedding: emb });
    }
    this.enrolled = flat;
    this.lastReload = Date.now();
  }

  /**
   * Per-person nearest-neighbour match with a margin guard.
   * Nearest pose is still the metric (same as calibrate.js), but computed PER
   * PERSON so we can compare the two closest people. A match is only accepted
   * when the nearest person is below threshold AND beats the 2nd-nearest person
   * by `margin` — otherwise the frame is ambiguous (two people embedding-close)
   * and we return unknown rather than guess wrong.
   */
  matchEmbedding(query: number[]): MatchResult {
    // nearest distance to each person
    const nearestByStaff = new Map<string, { name: string; dist: number }>();
    for (const e of this.enrolled) {
      const d = l2Distance(query, e.embedding);
      const cur = nearestByStaff.get(e.staff_id);
      if (!cur || d < cur.dist) nearestByStaff.set(e.staff_id, { name: e.full_name, dist: d });
    }
    if (nearestByStaff.size === 0) return { matched: false, name: 'unknown', distance: Infinity };

    const ranked = [...nearestByStaff.entries()]
      .map(([staff_id, v]) => ({ staff_id, ...v }))
      .sort((a, b) => a.dist - b.dist);

    const best = ranked[0];
    const second = ranked[1];

    const belowThreshold = best.dist < this.threshold;
    const clearWinner = !second || second.dist - best.dist >= this.margin;

    if (belowThreshold && clearWinner) {
      return { matched: true, staff_id: best.staff_id, name: best.name, distance: best.dist };
    }
    // Ambiguous or too far → unknown (report nearest distance for visibility).
    return { matched: false, name: 'unknown', distance: best.dist };
  }

  /** Majority vote over the last `voteWindow` frames; needs `voteMin` agreeing. */
  private voted(latest: MatchResult): MatchResult {
    this.votes.push(latest);
    if (this.votes.length > this.voteWindow) this.votes.shift();

    const counts = new Map<string, number>();
    for (const v of this.votes) {
      const key = v.matched ? `staff:${v.staff_id}` : 'unknown';
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    let winnerKey = 'unknown';
    let winnerCount = 0;
    for (const [key, c] of counts) {
      if (c > winnerCount) {
        winnerKey = key;
        winnerCount = c;
      }
    }
    // A staff identity must clear voteMin; otherwise stay unknown.
    if (winnerKey !== 'unknown' && winnerCount >= this.voteMin) {
      // emit the most recent frame that matched this identity (for its distance)
      for (let i = this.votes.length - 1; i >= 0; i--) {
        const v = this.votes[i];
        if (v.matched && `staff:${v.staff_id}` === winnerKey) return v;
      }
    }
    return { matched: false, name: 'unknown', distance: latest.distance };
  }

  private async loop(): Promise<void> {
    while (this.isRunning) {
      try {
        if (Date.now() - this.lastReload > this.reloadMs) await this.loadEnrolled();
        if (this.enrolled.length > 0) await this.detectOnce();
      } catch (err) {
        // A bad frame / network blip must never crash spine.
        console.error(`[FaceRecognition] cycle error: ${(err as Error).message}`);
      }
      await new Promise(r => setTimeout(r, this.cadenceMs));
    }
  }

  private async detectOnce(): Promise<void> {
    const frame = await this.captureFrame();
    if (!frame) return;

    // SHARED pipeline — same face-api path as enrollment. Requires exactly 1 face;
    // returns ok:false for 0 or >1 faces (skip those frames).
    const result = await extractEmbedding(frame);
    if (!result.ok || !result.embedding) {
      // No (single) face this frame. Age out the vote window so the next person
      // to appear doesn't inherit the previous person's votes.
      this.noFaceStreak++;
      if (this.noFaceStreak >= this.voteWindow) {
        this.votes = [];
        this.lastEmitKey = ''; // allow a fresh emit when someone returns
      }
      return;
    }
    this.noFaceStreak = 0;

    const raw = this.matchEmbedding(result.embedding);
    this.maybeEmit(this.voted(raw)); // temporal smoothing before emit
  }

  /** Grab one complete JPEG from the robot /snapshot endpoint (no MJPEG boundary parsing). */
  private async captureFrame(): Promise<Buffer | null> {
    try {
      const res = await fetch(`http://${this.robotIP}:${this.cameraPort}/snapshot`, {
        signal: AbortSignal.timeout(FACE_CONFIG.frame_timeout_ms),
      });
      if (!res.ok) return null;
      const buf = Buffer.from(await res.arrayBuffer());
      // Validate JPEG markers before handing to face-api.
      if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== 0xd8) return null;
      return buf;
    } catch {
      return null; // camera unreachable / timeout — skip this cycle
    }
  }

  /** Debounced emit: on identity change, or re-confirm same identity every reEmitMs. */
  private maybeEmit(match: MatchResult): void {
    const key = match.matched ? `staff:${match.staff_id}` : 'unknown';
    const now = Date.now();
    if (key === this.lastEmitKey && now - this.lastEmitAt < this.reEmitMs) return;
    this.lastEmitKey = key;
    this.lastEmitAt = now;

    const payload = match.matched
      ? { staff_id: match.staff_id, name: match.name, distance: Number(match.distance.toFixed(3)) }
      : { name: 'unknown', distance: Number(match.distance.toFixed(3)) };

    console.log(
      `[FaceRecognition] ${match.matched ? '✅ ' + match.name : '❓ unknown'} (L2 ${match.distance.toFixed(3)})`
    );
    this.emit({ type: 'face_detected', payload, timestamp: now });
  }
}
