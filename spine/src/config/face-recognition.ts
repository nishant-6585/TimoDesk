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
  // L2 threshold, CALIBRATED on real enrolled faces (3 people × 5 poses) via
  // scripts/enroll/calibrate.js on 2026-06-16. Nearest-neighbour gap was
  // [genuine.max 0.552, impostor.min 0.584]; 0.57 is the gap midpoint.
  // Recognizer rule: nearest enrolled distance < threshold → match; ≥ → unknown.
  // Re-run calibrate.js and update THIS value if enrollment data changes.
  threshold: 0.57, // single source of truth — do not hardcode elsewhere
  min_confidence: 0.50, // Require 50%+ confidence to identify staff
  confidence_clip: true, // Clip confidence to [0, 1]

  // Detection
  detection_cadence_ms: 1500, // Detect every 1.5s
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
 * Calibration notes (real data, 3 people × 5 poses, 2026-06-16):
 * - Match by NEAREST enrolled embedding (not all-pairwise); L2 < threshold = match.
 * - Genuine nearest-neighbour : 0.256–0.552 (mean 0.342)
 * - Impostor nearest-neighbour: 0.584–0.714 (mean 0.640)
 * - Clean gap [0.552, 0.584]; rank-1 accuracy 15/15 = 100%.
 * - Threshold 0.57 = gap midpoint. Margin is ~0.015 each side with only 3
 *   people; re-run scripts/enroll/calibrate.js as more staff enroll and retune.
 */
