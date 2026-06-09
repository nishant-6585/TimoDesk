/**
 * Face Recognition Service
 *
 * Real-time face detection + staff matching via L2 distance
 * Emits face_detected events over WebSocket
 */

import { SupabaseClient } from '@supabase/supabase-js';
import axios from 'axios';
import sharp from 'sharp';

export interface FaceDetectionResult {
  staff_id?: string;
  name?: string;
  confidence: number; // 0-1, higher = more likely a match
  anonymous?: boolean;
}

export class FaceRecognitionService {
  private readonly robotIP: string;
  private readonly cameraPort: number = 8080;
  private readonly threshold: number = 0.6; // L2 distance threshold (tunable)
  private readonly cadenceMs: number = 1500; // Detect every 1.5s
  private supabase: SupabaseClient;
  private staffEmbeddings: Map<
    string,
    { staff_id: string; full_name: string; embedding: number[] }[]
  > = new Map();
  private lastDetectionTime: number = 0;
  private isRunning: boolean = false;

  constructor(robotIP: string, supabase: SupabaseClient) {
    this.robotIP = robotIP;
    this.supabase = supabase;
  }

  /**
   * Start the face recognition pipeline
   */
  async start() {
    console.log('[FaceRecognition] Starting...');

    // Load staff embeddings from Supabase
    await this.loadStaffEmbeddings();

    if (this.staffEmbeddings.size === 0) {
      console.log('[FaceRecognition] No staff embeddings found. Waiting for enrollment.');
      return;
    }

    this.isRunning = true;
    console.log(`[FaceRecognition] ✅ Running (${this.staffEmbeddings.size} staff enrolled)`);

    // Start detection loop
    this.detectionLoop();
  }

  /**
   * Load staff face embeddings from Supabase
   */
  private async loadStaffEmbeddings() {
    const { data, error } = await this.supabase
      .from('staff_face_embedding')
      .select('staff_id, embedding');

    if (error) {
      console.error(`[FaceRecognition] Failed to load embeddings: ${error.message}`);
      return;
    }

    // Group by staff_id
    const embeddings = new Map<
      string,
      { staff_id: string; full_name: string; embedding: number[] }[]
    >();

    for (const row of data || []) {
      const { staff_id, embedding } = row as any;

      if (!embeddings.has(staff_id)) {
        embeddings.set(staff_id, []);
      }

      embeddings.get(staff_id)!.push({
        staff_id,
        full_name: '', // Will be populated from staff table
        embedding,
      });
    }

    // Get staff names
    const staffIds = Array.from(embeddings.keys());
    const { data: staffData } = await this.supabase
      .from('staff')
      .select('id, full_name')
      .in('id', staffIds);

    for (const staff of staffData || []) {
      const embs = embeddings.get(staff.id) || [];
      embs.forEach(e => {
        e.full_name = staff.full_name;
      });
    }

    this.staffEmbeddings = embeddings;
    console.log(`[FaceRecognition] Loaded embeddings: ${staffIds.length} staff`);
  }

  /**
   * Main detection loop
   */
  private async detectionLoop() {
    while (this.isRunning) {
      const now = Date.now();

      // Enforce cadence
      if (now - this.lastDetectionTime >= this.cadenceMs) {
        try {
          await this.detectFrame();
          this.lastDetectionTime = now;
        } catch (err) {
          console.error(`[FaceRecognition] Detection error: ${(err as Error).message}`);
        }
      }

      // Sleep briefly to avoid busy-loop
      await new Promise(r => setTimeout(r, 100));
    }
  }

  /**
   * Detect faces in current MJPEG frame
   */
  private async detectFrame() {
    try {
      // Fetch MJPEG frame from robot camera
      const frameBuffer = await this.captureFrame();
      if (!frameBuffer) return;

      // TODO: Run face detection (awaits real face-api integration)
      // For now, generate mock detection results
      const mockResult = this.generateMockDetection();

      if (mockResult) {
        // Emit event
        console.log(
          `[FaceRecognition] Detected: ${mockResult.name || 'visitor'} (${(mockResult.confidence * 100).toFixed(0)}%)`
        );
      }
    } catch (err) {
      // Silent fail - camera may not be available
    }
  }

  /**
   * Capture frame from MJPEG stream (robust boundary + Content-Length parsing)
   */
  private async captureFrame(): Promise<Buffer | null> {
    try {
      const url = `http://${this.robotIP}:${this.cameraPort}/stream`;
      const response = await axios.get(url, {
        responseType: 'stream',
        timeout: 5000,
      });

      // Parse MJPEG: read until we find Content-Length, then read exact bytes
      const buffer = await new Promise<Buffer>((resolve, reject) => {
        let accumulated = Buffer.alloc(0);
        let contentLength = 0;
        let readingJpeg = false;
        let jpegData = Buffer.alloc(0);

        response.data.on('data', (chunk: Buffer) => {
          accumulated = Buffer.concat([accumulated, chunk]);

          while (accumulated.length > 0) {
            // If we're already reading a JPEG
            if (readingJpeg) {
              const remaining = contentLength - jpegData.length;
              if (accumulated.length >= remaining) {
                jpegData = Buffer.concat([jpegData, accumulated.slice(0, remaining)]);
                resolve(jpegData);
                response.data.destroy();
                return;
              } else {
                jpegData = Buffer.concat([jpegData, accumulated]);
                accumulated = Buffer.alloc(0);
                break;
              }
            }

            // Look for Content-Length header
            const headerEnd = accumulated.indexOf('\r\n\r\n');
            if (headerEnd >= 0) {
              const header = accumulated.slice(0, headerEnd).toString('utf-8');
              const lengthMatch = header.match(/Content-Length:\s*(\d+)/i);

              if (lengthMatch) {
                contentLength = parseInt(lengthMatch[1], 10);
                accumulated = accumulated.slice(headerEnd + 4);
                readingJpeg = true;

                // Check if we already have enough data
                if (accumulated.length >= contentLength) {
                  resolve(accumulated.slice(0, contentLength));
                  response.data.destroy();
                  return;
                } else {
                  jpegData = accumulated;
                  accumulated = Buffer.alloc(0);
                }
              } else {
                // No Content-Length found, skip this chunk
                accumulated = accumulated.slice(headerEnd + 4);
              }
            } else {
              // Not enough data for full header yet
              break;
            }
          }
        });

        response.data.on('error', reject);
        setTimeout(() => reject(new Error('Frame capture timeout')), 3000);
      });

      return buffer;
    } catch (err) {
      console.error(`[FaceRecognition] Frame capture failed: ${(err as Error).message}`);
      return null;
    }
  }

  /**
   * Generate mock detection result (until real face-api integration)
   */
  private generateMockDetection(): FaceDetectionResult | null {
    // Randomly simulate staff detections for testing
    if (Math.random() < 0.1) {
      const staffArray = Array.from(this.staffEmbeddings.values()).flat();
      if (staffArray.length > 0) {
        const staff = staffArray[Math.floor(Math.random() * staffArray.length)];
        return {
          staff_id: staff.staff_id,
          name: staff.full_name,
          confidence: 0.7 + Math.random() * 0.3,
        };
      }
    }

    return null;
  }

  /**
   * Real face detection (stub - awaits face-api integration)
   */
  private async detectFacesInFrame(frameBuffer: Buffer): Promise<any[]> {
    // TODO: Use face-api.js to detect faces in frameBuffer
    // Return array of {embedding: number[], box: {x, y, width, height}}
    return [];
  }

  /**
   * Match embedding against staff database
   */
  private matchEmbedding(embedding: number[]): FaceDetectionResult | null {
    let bestMatch: FaceDetectionResult | null = null;
    let bestDistance = Infinity;

    for (const staffEmbeddings of this.staffEmbeddings.values()) {
      for (const staffEmb of staffEmbeddings) {
        const distance = this.l2Distance(embedding, staffEmb.embedding);

        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = {
            staff_id: staffEmb.staff_id,
            name: staffEmb.full_name,
            confidence: 1 - Math.min(1, bestDistance), // Normalize distance to confidence
          };
        }
      }
    }

    // Only return if below threshold
    if (bestMatch && bestDistance <= this.threshold) {
      return bestMatch;
    }

    return null;
  }

  /**
   * L2 (Euclidean) distance between vectors
   */
  private l2Distance(a: number[], b: number[]): number {
    let sum = 0;
    for (let i = 0; i < a.length; i++) {
      const diff = a[i] - b[i];
      sum += diff * diff;
    }
    return Math.sqrt(sum);
  }

  stop() {
    this.isRunning = false;
    console.log('[FaceRecognition] Stopped');
  }
}
