/**
 * Face Recognition Configuration
 * Tunable parameters for real-time face detection + staff matching
 */

export const FACE_CONFIG = {
  // Model + embedding
  model: 'face-api',
  embedding_dim: 128, // matches migration 006 (vector(128)) + face-api descriptor
  metric: 'euclidean', // L2 distance

  // Matching
  // L2 threshold. Re-checked on 6 people / 28 poses (2026-06-17): the nearest-
  // neighbour distributions now OVERLAP slightly — genuine.max 0.557 vs
  // impostor.min 0.536 (closest pair Rakesh↔rohit), gap -0.021. Rank-1 is still
  // 100%, so with the margin guard + voting the recognizer matches correctly,
  // but a global threshold can't cleanly separate. Set to 0.53 (just below the
  // closest impostor) to PRIORITIZE PRECISION: rejects the 0.536 collision →
  // no "wrong name" false matches, at the cost of occasionally showing
  // "unknown" for a genuine person at an awkward angle (safer for reception).
  // To restore a clean positive gap, re-enroll the loose/short captures
  // (rohit + Amit have only 4 poses) sharper + more frontal, then re-run
  // calibrate.js and raise this back toward the gap midpoint.
  threshold: 0.53, // single source of truth — do not hardcode elsewhere
  min_confidence: 0.50, // Require 50%+ confidence to identify staff
  confidence_clip: true, // Clip confidence to [0, 1]

  // Precision guards (reduce false matches when two people are embedding-close):
  // - match_margin: the nearest person must beat the 2nd-nearest person by at
  //   least this L2 gap, else the frame is "ambiguous" → unknown (don't guess).
  // - vote_window / vote_min: a candidate identity must win at least vote_min of
  //   the last vote_window frames before it's emitted (kills single-frame flips).
  match_margin: 0.06,
  vote_window: 5,
  vote_min: 3,

  // Detection
  detection_cadence_ms: 1000, // Detect every 1.0s (faster so voting isn't sluggish)
  frame_timeout_ms: 5000, // Timeout for frame capture
  camera_port: 8080, // MJPEG stream port

  // Events
  emit_anonymous: true, // Emit events for unidentified visitors
  emit_confidence: true, // Include confidence score in events

  // Logging
  log_detections: true,
  log_fps: false,
};

/**
 * Calibration notes (real data, 6 people / 28 poses, 2026-06-17):
 * - Match by NEAREST enrolled embedding (not all-pairwise); L2 < threshold = match.
 * - Genuine nearest-neighbour : 0.256–0.557 (mean 0.372)
 * - Impostor nearest-neighbour: 0.536–0.647 (mean 0.596)
 * - Distributions now OVERLAP (gap -0.021): genuine.max 0.557 > impostor.min
 *   0.536 (Rakesh↔rohit). Rank-1 still 100%, so nearest-neighbour + margin guard
 *   + voting recognise correctly; the global threshold just can't fully separate.
 * - Threshold 0.53 chosen for PRECISION (reject the 0.536 collision; occasional
 *   "unknown" instead of a wrong name). Re-enroll the loose/short captures
 *   (rohit, Amit = 4 poses) and re-run calibrate.js to restore a positive gap.
 */
