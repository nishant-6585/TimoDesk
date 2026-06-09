/**
 * Part A: Staff Face Enrollment Pipeline
 *
 * Enroll staff faces into staff_face_embedding with consent tracking.
 * Works with real staff photos OR test data (LFW).
 *
 * Usage:
 *   npx ts-node spine/scripts/enroll/enroll.ts --consent-manifest consent_manifest.json
 *
 * Folder structure:
 *   photos/
 *   ├── alice-johnson/
 *   │   ├── 1.jpg
 *   │   ├── 2.jpg
 *   │   └── 3.jpg
 *   └── bob-smith/
 *       ├── 1.jpg
 *       └── 2.jpg
 */

import * as faceapi from '@vladmandic/face-api';
import * as canvas from 'canvas';
import fs from 'fs';
import path from 'path';
import { createClient } from '@supabase/supabase-js';

// Patch canvas for face-api
faceapi.env.monkeyPatch({
  Canvas: canvas.Canvas,
  Image: canvas.Image,
  ImageData: canvas.ImageData,
});

const PHOTOS_DIR = path.join(__dirname, 'photos');
const CONSENT_FILE = process.argv[process.argv.indexOf('--consent-manifest') + 1] || path.join(__dirname, 'consent_manifest.json');

interface ConsentEntry {
  full_name: string;
  role: string;
  notify_channel: string;
  consent_ref: string;
  consent_at: string;
  consent_method: string;
}

interface EnrollmentStats {
  staff_id: string;
  full_name: string;
  photos_accepted: number;
  photos_rejected: number;
  embeddings_inserted: number;
}

let stats: EnrollmentStats[] = [];

async function loadModels() {
  console.log('[Enroll] Loading face-api models...');

  const modelPath = path.join(__dirname, '../../node_modules/@vladmandic/face-api/model');

  await faceapi.nets.tinyFaceDetector.loadFromUri(modelPath);
  await faceapi.nets.faceLandmark68Net.loadFromUri(modelPath);
  await faceapi.nets.faceRecognitionNet.loadFromUri(modelPath);

  console.log('✅ Models loaded\n');
}

async function enrollStaff() {
  // Load Supabase client
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    throw new Error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
  }

  const supabase = createClient(supabaseUrl, supabaseKey);

  // Load consent manifest
  if (!fs.existsSync(CONSENT_FILE)) {
    throw new Error(`❌ Consent manifest not found: ${CONSENT_FILE}`);
  }

  const consentManifest: Record<string, ConsentEntry> = JSON.parse(fs.readFileSync(CONSENT_FILE, 'utf-8'));
  console.log(`[Enroll] Loaded consent manifest with ${Object.keys(consentManifest).length} staff\n`);

  // Load face detection/embedding models
  await loadModels();

  // Process each staff folder
  if (!fs.existsSync(PHOTOS_DIR)) {
    throw new Error(`❌ Photos directory not found: ${PHOTOS_DIR}`);
  }

  const staffFolders = fs.readdirSync(PHOTOS_DIR).filter(f =>
    fs.statSync(path.join(PHOTOS_DIR, f)).isDirectory()
  );

  console.log(`[Enroll] Processing ${staffFolders.length} staff folders...\n`);

  for (const staffFolder of staffFolders) {
    const staffId = staffFolder;
    const consent = consentManifest[staffId];

    if (!consent) {
      console.log(`⚠️  ${staffId}: No consent found in manifest (skipped)`);
      continue;
    }

    if (!consent.consent_ref || !consent.consent_at) {
      console.log(`⚠️  ${staffId}: Missing consent_ref or consent_at (skipped)`);
      continue;
    }

    console.log(`[Enroll] Processing ${consent.full_name}...`);

    // Upsert staff row
    const { data: staffRow, error: staffError } = await supabase
      .from('staff')
      .upsert(
        {
          id: staffId,
          full_name: consent.full_name,
          role: consent.role,
          notify_channel: consent.notify_channel,
          active: true,
        },
        { onConflict: 'id' }
      )
      .select('id')
      .single();

    if (staffError) {
      console.log(`❌ ${consent.full_name}: Failed to upsert staff row: ${staffError.message}`);
      continue;
    }

    const realStaffId = staffRow.id;

    // Process photos
    const photosPath = path.join(PHOTOS_DIR, staffFolder);
    const photos = fs.readdirSync(photosPath)
      .filter(f => /\.(jpg|jpeg|png)$/i.test(f))
      .sort();

    let accepted = 0;
    let rejected = 0;

    for (const photo of photos) {
      try {
        const photoPath = path.join(photosPath, photo);
        const imageBuffer = fs.readFileSync(photoPath);
        const image = await canvas.loadImage(imageBuffer);

        // Detect face
        const detections = await faceapi.detectSingleFace(image as any, new faceapi.TinyFaceDetectorOptions())
          .withFaceLandmarks()
          .withFaceDescriptors();

        if (!detections) {
          console.log(`  ⚠️  ${photo}: No face detected (rejected)`);
          rejected++;
          continue;
        }

        // Extract 128-dim descriptor
        const descriptor = Array.from(detections.descriptor);

        if (descriptor.length !== 128) {
          console.log(`  ❌ ${photo}: Invalid descriptor dimension ${descriptor.length} (rejected)`);
          rejected++;
          continue;
        }

        // Insert embedding
        const { error: embedError } = await supabase
          .from('staff_face_embedding')
          .insert({
            staff_id: realStaffId,
            embedding: descriptor,
            consent_at: new Date(consent.consent_at).toISOString(),
            consent_ref: consent.consent_ref,
          });

        if (embedError) {
          console.log(`  ❌ ${photo}: Failed to insert embedding: ${embedError.message}`);
          rejected++;
          continue;
        }

        accepted++;
        console.log(`  ✅ ${photo}: Embedded (1/128-dim descriptor)`);
      } catch (err) {
        console.log(`  ❌ ${photo}: Error: ${(err as Error).message}`);
        rejected++;
      }
    }

    stats.push({
      staff_id: staffId,
      full_name: consent.full_name,
      photos_accepted: accepted,
      photos_rejected: rejected,
      embeddings_inserted: accepted,
    });

    console.log(`  📊 ${consent.full_name}: ${accepted}/${photos.length} photos enrolled (${accepted} embeddings)\n`);
  }

  // Summary
  console.log('\n════════════════════════════════════════════════════════════════');
  console.log('ENROLLMENT SUMMARY');
  console.log('════════════════════════════════════════════════════════════════\n');

  let totalPhotos = 0;
  let totalEmbeddings = 0;

  stats.forEach(s => {
    console.log(`✅ ${s.full_name}: ${s.photos_accepted}/${s.photos_accepted + s.photos_rejected} photos → ${s.embeddings_inserted} embeddings`);
    totalPhotos += s.photos_accepted + s.photos_rejected;
    totalEmbeddings += s.embeddings_inserted;
  });

  console.log(`\n✅ TOTAL: ${stats.length} staff, ${totalPhotos} photos processed, ${totalEmbeddings} embeddings enrolled`);
  console.log('════════════════════════════════════════════════════════════════\n');

  // If test data, show purge command
  const isTestData = Object.values(consentManifest).some(c => c.consent_ref.startsWith('TEST-'));
  if (isTestData) {
    console.log('⚠️  TEST DATA DETECTED\n');
    console.log('To purge all test embeddings before go-live, run:\n');
    console.log('  npx supabase db push');
    console.log('  delete from staff_face_embedding where consent_ref like \'TEST-%\';');
    console.log('  delete from staff where id like \'test-%\';');
    console.log('\n');
  }
}

enrollStaff().catch(err => {
  console.error(`\n❌ Enrollment failed: ${err.message}`);
  process.exit(1);
});
