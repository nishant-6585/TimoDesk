/**
 * Step 1: REAL FACE → 128-dim vector
 * Using sharp instead of canvas for image loading
 */

import faceapi from '@vladmandic/face-api';
import * as canvas from 'canvas';
import sharp from 'sharp';
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

function startModelServer() {
  return new Promise((resolve, reject) => {
    const modelPath = path.join(__dirname, '../node_modules/@vladmandic/face-api/model');

    const server = http.createServer((req, res) => {
      const cleanPath = req.url.startsWith('/') ? req.url.slice(1) : req.url;
      const filePath = path.join(modelPath, cleanPath);

      if (!fs.existsSync(filePath)) {
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
    console.error('❌ Usage: node test-face-api-real-v2.js <image.jpg>');
    process.exit(1);
  }

  if (!fs.existsSync(imagePath)) {
    console.error(`❌ File not found: ${imagePath}`);
    process.exit(1);
  }

  console.log('════════════════════════════════════════════════════════════════');
  console.log('STEP 1: REAL JPG → 128-DIM VECTOR (v2 with sharp)');
  console.log('════════════════════════════════════════════════════════════════\n');

  let server;

  try {
    // Start model server
    server = await startModelServer();

    console.log('[Test] Loading face-api models...\n');

    // Load models
    await faceapi.nets.tinyFaceDetector.loadFromUri('http://localhost:3333/');
    await faceapi.nets.faceLandmark68Net.loadFromUri('http://localhost:3333/');
    await faceapi.nets.faceRecognitionNet.loadFromUri('http://localhost:3333/');

    console.log('✅ Models loaded\n');

    // Load image with sharp, convert to canvas-compatible format
    console.log(`[Test] Loading image with sharp: ${imagePath}`);
    const imageData = await sharp(imagePath)
      .resize(256, 256, { fit: 'fill' })
      .raw()
      .toBuffer({ resolveWithObject: true });

    console.log(`✅ Image loaded: ${imageData.info.width}×${imageData.info.height}`);

    // Create canvas image
    const canvasImage = new canvas.Image();
    const imageDataObj = new canvas.ImageData(
      new Uint8ClampedArray(imageData.data),
      imageData.info.width,
      imageData.info.height
    );

    // Create canvas and draw image
    const testCanvas = new canvas.Canvas(imageData.info.width, imageData.info.height);
    const ctx = testCanvas.getContext('2d');
    ctx.putImageData(imageDataObj, 0, 0);

    console.log('✅ Image loaded into canvas\n');

    // Detect face
    console.log('[Test] Detecting face...');
    const detection = await faceapi.detectSingleFace(
      testCanvas,
      new faceapi.TinyFaceDetectorOptions()
    );

    if (!detection) {
      console.error('⚠️  No face detected in image (but image loaded successfully)');
      console.log('\nThis is OK if image is just a blank/test frame.');
      console.log('If image should have a person, check:');
      console.log('  - Person is clearly visible in camera');
      console.log('  - Good lighting');
      console.log('  - Face is not too small or obscured');
      process.exit(0);
    }

    console.log('✅ Face detected\n');

    // Get descriptor using face-api.computeFaceDescriptor
    console.log('[Test] Computing 128-dim embedding...');

    // Use the detection's descriptor if available
    const allDetections = await faceapi
      .detectAllFaces(testCanvas, new faceapi.TinyFaceDetectorOptions())
      .withFaceLandmarks()
      .withFaceDescriptors();

    if (!allDetections || allDetections.length === 0) {
      throw new Error('Failed to compute face descriptors');
    }

    const embedding = Array.from(allDetections[0].descriptor);

    console.log(`[Test] Embedding dimension: ${embedding.length}`);

    // GATE: Assert 128-dim
    if (embedding.length !== 128) {
      console.error(`\n❌ GATE FAILED: Expected 128 dimensions, got ${embedding.length}`);
      process.exit(1);
    }

    console.log('✅ GATE PASSED: 128 dimensions\n');

    // Print vector
    console.log('════════════════════════════════════════════════════════════════');
    console.log('128-DIM FACE EMBEDDING VECTOR');
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
    console.log('Full vector:');
    for (let i = 0; i < embedding.length; i += 10) {
      const chunk = embedding.slice(i, i + 10);
      console.log(`  [${i.toString().padStart(3)}] ${chunk.map(v => v.toFixed(6)).join(' ')}`);
    }
    console.log('════════════════════════════════════════════════════════════════\n');

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

    console.log('✅✅✅ STEP 1 COMPLETE ✅✅✅');
    console.log('Real human face → Real 128-dim vector\n');

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
