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
}

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

    return {
      ok: true,
      embedding,
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
