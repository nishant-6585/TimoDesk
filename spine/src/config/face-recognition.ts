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
  // L2 threshold, CALIBRATED on real enrolled faces (4 people, 19 poses) via
  // scripts/enroll/calibrate.js on 2026-06-16. Nearest-neighbour gap was
  // [genuine.max 0.557, impostor.min 0.572]; 0.56 is the gap midpoint.
  // Gap is thin (0.014) — the match_margin + voting guards below do the heavy
  // lifting against inference noise. Recognizer rule: nearest enrolled distance
  // < threshold → match; ≥ → unknown. Re-run calibrate.js if enrollment changes.
  threshold: 0.56, // single source of truth — do not hardcode elsewhere
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
 * Calibration notes (real data, 4 people / 19 poses, 2026-06-16):
 * - Match by NEAREST enrolled embedding (not all-pairwise); L2 < threshold = match.
 * - Genuine nearest-neighbour : 0.256–0.557 (mean 0.358)
 * - Impostor nearest-neighbour: 0.572–0.696 (mean 0.614)
 * - Clean gap [0.557, 0.572]; rank-1 accuracy 19/19 = 100%.
 * - Threshold 0.56 = gap midpoint. Gap is razor-thin (~0.014) so two people are
 *   embedding-close; match_margin + voting carry inference robustness. Re-run
 *   scripts/enroll/calibrate.js as staff enroll and retune.
 */
