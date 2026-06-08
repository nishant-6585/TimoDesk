/**
 * camera.ts — Mock MJPEG camera server (port 8080)
 * Generates minimal JPEG frames for development/testing
 */

import http from 'http';

const CAMERA_PORT = 8080;
const FRAME_INTERVAL_MS = 100; // 10 FPS

// Minimal valid JPEG frame (smallest possible size that parsers accept)
function generateFakeJpegFrame(): Buffer {
  // JPEG structure: SOI(0xFFD8) ... EOI(0xFFD9)
  // This is a valid but minimal JPEG that most parsers will accept
  return Buffer.from([
    0xFF, 0xD8, // SOI (Start of Image)
    0xFF, 0xE0, // APP0
    0x00, 0x10, // Length
    0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
    0x01, 0x01, // Version 1.1
    0x00, // No units
    0x00, 0x01, // X density
    0x00, 0x01, // Y density
    0x00, 0x00, // Thumbnail 0x0
    0xFF, 0xD9, // EOI (End of Image)
  ]);
}

export function startCameraServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      if (req.url === '/stream') {
        console.log('[Camera] Client connected to /stream');

        res.writeHead(200, {
          'Content-Type': 'multipart/x-mixed-replace; boundary=BOUNDARY',
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        });

        // Send fake MJPEG frames
        const frameInterval = setInterval(() => {
          const frame = generateFakeJpegFrame();
          const header = `--BOUNDARY\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n`;

          try {
            res.write(header);
            res.write(frame);
            res.write('\r\n');
          } catch (e) {
            clearInterval(frameInterval);
            res.end();
          }
        }, FRAME_INTERVAL_MS);

        req.on('close', () => {
          console.log('[Camera] Client disconnected');
          clearInterval(frameInterval);
          res.end();
        });
      } else {
        res.writeHead(404);
        res.end('Not found');
      }
    });

    server.listen(CAMERA_PORT, () => {
      console.log(`✓ Camera stream (MJPEG) listening on port ${CAMERA_PORT}`);
      resolve();
    });

    server.on('error', reject);
  });
}
