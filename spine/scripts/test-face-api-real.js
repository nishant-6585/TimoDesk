/**
 * Step 1: PROOF OF WORK — Real JPG → 128-dim vector
 *
 * Gate: Print real float vector, assert length===128
 * No mocks. No "models loaded". Real output or fail.
 *
 * Usage:
 *   node test-face-api-real.js <image.jpg>
 *   node test-face-api-real.js ./enroll/photos/test-identity-1/1.jpg
 */

import faceapi from '@vladmandic/face-api';
import * as canvas from 'canvas';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import http from 'http';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Patch canvas for face-api
faceapi.env.monkeyPatch({
  Canvas: canvas.Canvas,
  Image: canvas.Image,
  ImageData: canvas.ImageData,
});

// Start HTTP server to serve models (since file:// doesn't work with fetch)
function startModelServer() {
  return new Promise((resolve, reject) => {
    // Models are in spine/node_modules/@vladmandic/face-api/model
    // __dirname is spine/scripts, so go up to spine, then into node_modules
    const modelPath = path.join(__dirname, '../node_modules/@vladmandic/face-api/model');

    console.log(`[Debug] Model path: ${modelPath}`);
    if (!fs.existsSync(modelPath)) {
      reject(new Error(`Model path not found: ${modelPath}`));
      return;
    }

    const server = http.createServer((req, res) => {
      // Clean up URL (remove leading /)
      const cleanPath = req.url.startsWith('/') ? req.url.slice(1) : req.url;
      const filePath = path.join(modelPath, cleanPath);

      // Log request
      // console.log(`[Server] GET ${req.url} -> ${filePath}`);

      if (!fs.existsSync(filePath)) {
        console.log(`[Server] 404: ${filePath}`);
        res.writeHead(404);
        res.end('Not found');
        return;
      }

      try {
        const file = fs.readFileSync(filePath);
        res.writeHead(200, {
          'Content-Type': 'application/octet-stream',
          'Content-Length': file.length,
        });
        res.end(file);
      } catch (err) {
        console.log(`[Server] Error reading file: ${err}`);
        res.writeHead(500);
        res.end('Error');
      }
    });

    server.listen(3333, () => {
      console.log('[Test] Model server running on http://localhost:3333/');
      resolve(server);
    });

    server.on('error', reject);
  });
}

async function testFaceApi() {
  const imagePath = process.argv[2];

  if (!imagePath) {
    console.error('❌ Usage: node test-face-api-real.js <image.jpg>');
    process.exit(1);
  }

  if (!fs.existsSync(imagePath)) {
    console.error(`❌ File not found: ${imagePath}`);
    process.exit(1);
  }

  console.log('════════════════════════════════════════════════════════════════');
  console.log('STEP 1: REAL JPG → 128-DIM VECTOR');
  console.log('════════════════════════════════════════════════════════════════\n');

  let server;

  try {
    // Start model server
    server = await startModelServer();

    console.log('[Test] Loading face-api models from http://localhost:3333/...\n');

    // Load models from HTTP server
    await faceapi.nets.tinyFaceDetector.loadFromUri('http://localhost:3333/');
    await faceapi.nets.faceLandmark68Net.loadFromUri('http://localhost:3333/');
    await faceapi.nets.faceRecognitionNet.loadFromUri('http://localhost:3333/');

    console.log('✅ Models loaded\n');

    // Load image
    console.log(`[Test] Loading image: ${imagePath}`);
    const imageBuffer = fs.readFileSync(imagePath);
    const image = await canvas.loadImage(imageBuffer);
    console.log(`✅ Image loaded (${image.width}×${image.height})\n`);

    // Detect face + extract embedding
    console.log('[Test] Detecting face...');
    const detection = await faceapi
      .detectSingleFace(image, new faceapi.TinyFaceDetectorOptions());

    if (!detection) {
      console.error('❌ No face detected in image');
      process.exit(1);
    }

    console.log('✅ Face detected');
    console.log('[Test] Extracting embeddings...');

    // Get descriptors
    const labeledDescriptors = await faceapi.computeFaceDescriptor(image);

    if (!labeledDescriptors) {
      console.error('❌ Failed to compute face descriptor');
      process.exit(1);
    }

    console.log('✅ Descriptor computed\n');

    // Extract embedding
    const embedding = Array.from(labeledDescriptors);

    console.log(`[Test] Embedding dimensions: ${embedding.length}`);

    // GATE: Assert 128-dim
    if (embedding.length !== 128) {
      console.error(`\n❌ GATE FAILED: Expected 128 dimensions, got ${embedding.length}`);
      process.exit(1);
    }

    console.log('✅ GATE PASSED: 128 dimensions\n');

    // Print first 10 values + last 10 for inspection
    console.log('════════════════════════════════════════════════════════════════');
    console.log('EMBEDDING VECTOR (128-float)');
    console.log('════════════════════════════════════════════════════════════════\n');

    console.log('First 10 values:');
    console.log(
      embedding
        .slice(0, 10)
        .map((v, i) => `  [${i}] = ${v.toFixed(6)}`)
        .join('\n')
    );

    console.log('\n...\n');

    console.log('Last 10 values:');
    console.log(
      embedding
        .slice(-10)
        .map((v, i) => `  [${i + 118}] = ${v.toFixed(6)}`)
        .join('\n')
    );

    console.log('\n════════════════════════════════════════════════════════════════');
    console.log(`Full vector (${embedding.length} floats):`);
    console.log(embedding.map((v, i) => (i % 10 === 0 ? '\n  ' : '') + v.toFixed(6)).join(' '));
    console.log('\n════════════════════════════════════════════════════════════════\n');

    // Statistics
    const mean = embedding.reduce((a, b) => a + b) / embedding.length;
    const std = Math.sqrt(
      embedding.reduce((sum, v) => sum + (v - mean) ** 2, 0) / embedding.length
    );
    const min = Math.min(...embedding);
    const max = Math.max(...embedding);

    console.log('STATISTICS:');
    console.log(`  Mean: ${mean.toFixed(6)}`);
    console.log(`  Std:  ${std.toFixed(6)}`);
    console.log(`  Min:  ${min.toFixed(6)}`);
    console.log(`  Max:  ${max.toFixed(6)}\n`);

    console.log('✅ STEP 1 COMPLETE: Real JPG → Real 128-dim vector\n');

    process.exit(0);
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err));
    console.error(`\n❌ Error: ${error.message}`);
    console.error(`\nStack:\n${error.stack}`);
    process.exit(1);
  } finally {
    if (server) {
      server.close();
    }
  }
}

testFaceApi();
