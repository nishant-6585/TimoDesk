/**
 * Face Embedding Service — Shared extractor for enrollment + recognition
 *
 * Reused by:
 * - enrollment CLI (spine/scripts/enroll/enroll.js)
 * - HTTP /enroll endpoint (spine/src/server.ts)
 * - Recognition pipeline (spine/src/services/face-recognition.ts)
 *
 * Contract: IDENTICAL preprocessing + model for all callers, or matching breaks.
 */

// MUST precede the face-api import: restores util.is* helpers removed in Node 23+.
import '../util-polyfill';
import faceapi from '@vladmandic/face-api';
import * as canvas from 'canvas';

// CRITICAL: Monkey-patch face-api for Node.js environment
// Must run ONCE at module load before any detectAllFaces calls
const { Canvas, Image, ImageData } = canvas as any;
faceapi.env.monkeyPatch({ Canvas, Image, ImageData } as any);

export interface FaceEmbeddingResult {
  ok: boolean;
  embedding?: number[]; // 128-dim vector
  facesFound?: number; // For error: how many faces detected (expect exactly 1)
  error?: string;
  thumbnail?: Buffer; // Square JPEG crop of the face — UI display only, never used for matching
  faceBox?: { x: number; y: number; width: number; height: number }; // Detected face box in source pixels (quality gates)
}

// Display thumbnail config — square crop with margin, kept small for fast list loads.
const THUMB_SIZE = 200; // px (square)
const THUMB_MARGIN = 0.4; // expand the face box by 40% on each side for headroom
const THUMB_QUALITY = 0.82;

/**
 * Initialize face-api models (must be called once at startup)
 * Loads from HTTP server (modelServerUrl should be the base URL serving models)
 */
export async function initializeFaceModels(modelServerUrl: string): Promise<void> {
  await faceapi.nets.tinyFaceDetector.loadFromUri(`${modelServerUrl}/`);
  await faceapi.nets.faceLandmark68Net.loadFromUri(`${modelServerUrl}/`);
  await faceapi.nets.faceRecognitionNet.loadFromUri(`${modelServerUrl}/`);
}

/**
 * Extract 128-dim embedding from an image buffer
 *
 * Preprocessing:
 * - Resize to 256×256 (fit, no letterbox)
 * - RGB format
 * - Detect EXACTLY 1 face (return error if 0 or >1)
 * - Extract landmark-aligned 128-dim descriptor
 *
 * @param imageBuffer JPEG/PNG binary data
 * @returns { ok: true, embedding: number[] } or { ok: false, error: string, facesFound: number }
 */
export async function extractEmbedding(imageBuffer: Buffer): Promise<FaceEmbeddingResult> {
  try {
    // Load image with canvas
    const image = await canvas.loadImage(imageBuffer);

    // Draw at NATIVE size — do NOT squish to a square. Forcing a 4:3 camera
    // frame into 256×256 horizontally compresses the face and makes turned
    // (left/right) poses undetectable. Preserve aspect ratio.
    const nativeCanvas = new canvas.Canvas(image.width, image.height);
    const ctx = nativeCanvas.getContext('2d');
    ctx.drawImage(image as any, 0, 0);

    // Tuned detector: larger inputSize (must be a multiple of 32) + lower score
    // threshold so mildly turned / tilted faces are still detected.
    const detectorOptions = new faceapi.TinyFaceDetectorOptions({
      inputSize: 416,
      scoreThreshold: 0.4,
    });

    // Detect faces with tinyFaceDetector
    const detections = await faceapi
      .detectAllFaces(nativeCanvas, detectorOptions)
      .withFaceLandmarks()
      .withFaceDescriptors();

    // Gate: require EXACTLY 1 face
    if (detections.length === 0) {
      return {
        ok: false,
        facesFound: 0,
        error: 'No face detected in image',
      };
    }

    if (detections.length > 1) {
      return {
        ok: false,
        facesFound: detections.length,
        error: `Multiple faces detected (found ${detections.length}, expected exactly 1)`,
      };
    }

    // Extract 128-dim embedding from the single face
    const embedding = Array.from(detections[0].descriptor);

    // Verify dimension (safety check)
    if (embedding.length !== 128) {
      return {
        ok: false,
        error: `Invalid embedding dimension: got ${embedding.length}, expected 128`,
      };
    }

    // Build a square display thumbnail from the detected face box (best-effort —
    // a crop failure must never block enrollment). UI only, not for matching.
    let thumbnail: Buffer | undefined;
    try {
      thumbnail = cropFaceThumbnail(nativeCanvas, image, detections[0].detection.box);
    } catch (err) {
      console.warn(
        `[FaceEmbedding] Thumbnail crop failed (continuing without): ${err instanceof Error ? err.message : String(err)}`
      );
    }

    const box = detections[0].detection.box;
    return {
      ok: true,
      embedding,
      thumbnail,
      faceBox: { x: box.x, y: box.y, width: box.width, height: box.height },
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return {
      ok: false,
      error: `Face embedding failed: ${message}`,
    };
  }
}

/**
 * Crop a square, margin-padded JPEG thumbnail of the detected face for UI display.
 * `box` is face-api's detection box (x, y, width, height) in source-image pixels.
 */
function cropFaceThumbnail(
  source: canvas.Canvas,
  image: { width: number; height: number },
  box: { x: number; y: number; width: number; height: number }
): Buffer {
  // Expand to a square around the face center, then clamp to image bounds.
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  const half = (Math.max(box.width, box.height) * (1 + THUMB_MARGIN)) / 2;

  let sx = Math.round(cx - half);
  let sy = Math.round(cy - half);
  let side = Math.round(half * 2);

  // Clamp the crop rectangle inside the image so drawImage never reads OOB.
  sx = Math.max(0, Math.min(sx, image.width - 1));
  sy = Math.max(0, Math.min(sy, image.height - 1));
  side = Math.max(1, Math.min(side, image.width - sx, image.height - sy));

  const out = new canvas.Canvas(THUMB_SIZE, THUMB_SIZE);
  const octx = out.getContext('2d');
  octx.drawImage(source as any, sx, sy, side, side, 0, 0, THUMB_SIZE, THUMB_SIZE);
  return out.toBuffer('image/jpeg', { quality: THUMB_QUALITY });
}

/**
 * Detection-only presence probe (escort person-check): count faces in a frame.
 *
 * Runs ONLY the tinyFaceDetector pass — no landmarks, no descriptors, no
 * identity match, nothing stored (DPDP: visitor biometrics are never computed
 * or persisted; the frame and boxes are discarded after the count).
 */
export async function countFaces(imageBuffer: Buffer): Promise<number> {
  const image = await canvas.loadImage(imageBuffer);
  const nativeCanvas = new canvas.Canvas(image.width, image.height);
  nativeCanvas.getContext('2d').drawImage(image as any, 0, 0);

  const detectorOptions = new faceapi.TinyFaceDetectorOptions({
    inputSize: 416,
    scoreThreshold: 0.4,
  });
  const detections = await faceapi.detectAllFaces(nativeCanvas, detectorOptions);
  return detections.length;
}

/**
 * L2 (Euclidean) distance between two embeddings
 * Used by recognition pipeline to match embeddings
 */
export function l2Distance(a: number[], b: number[]): number {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const diff = a[i] - b[i];
    sum += diff * diff;
  }
  return Math.sqrt(sum);
}
