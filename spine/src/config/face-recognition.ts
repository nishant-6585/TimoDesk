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
  threshold: 0.60, // L2 distance threshold (tunable, calibrated during enrollment)
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
 * Calibration notes:
 * - L2 distance < threshold = match (same person)
 * - L2 distance >= threshold = no match (different people)
 *
 * Typical ranges (from calibration on test data):
 * - Self-match: 0.10-0.40 (same person, different photos)
 * - Cross-match: 0.60-0.95 (different people)
 * - Recommended threshold: 0.55 (midpoint)
 */
