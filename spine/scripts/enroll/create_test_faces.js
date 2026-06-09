/**
 * Create minimal test faces for enrollment pipeline validation
 * This generates simple placeholder images to test the flow
 * (Real photos needed before production)
 */

import fs from 'fs';
import path from 'path';
import { createCanvas } from 'canvas';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function createTestFace(name, photoNum) {
  // Create canvas with face-like features
  const canvas = createCanvas(256, 256);
  const ctx = canvas.getContext('2d');

  // Deterministic random seed based on name+number
  const seed = (name.charCodeAt(0) + photoNum) % 360;

  // Background
  ctx.fillStyle = '#f5f5f5';
  ctx.fillRect(0, 0, 256, 256);

  // Head (circle)
  ctx.fillStyle = `hsl(${seed}, 30%, 65%)`;
  ctx.beginPath();
  ctx.arc(128, 110, 50, 0, Math.PI * 2);
  ctx.fill();

  // Eyes
  ctx.fillStyle = '#333';
  ctx.beginPath();
  ctx.arc(110, 100, 6, 0, Math.PI * 2);
  ctx.fill();

  ctx.beginPath();
  ctx.arc(146, 100, 6, 0, Math.PI * 2);
  ctx.fill();

  // Nose
  ctx.strokeStyle = '#999';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(128, 105);
  ctx.lineTo(128, 125);
  ctx.stroke();

  // Mouth
  ctx.beginPath();
  ctx.arc(128, 140, 15, 0, Math.PI);
  ctx.stroke();

  // Text label
  ctx.fillStyle = '#333';
  ctx.font = '12px Arial';
  ctx.textAlign = 'center';
  ctx.fillText(name, 128, 200);
  ctx.fillText(`Photo ${photoNum}`, 128, 220);

  return canvas.toBuffer('image/jpeg');
}

async function main() {
  const photosDir = path.join(__dirname, 'photos');
  const identities = [
    'test-identity-1',
    'test-identity-2',
    'test-identity-3',
    'test-identity-4',
    'test-identity-5',
  ];

  console.log('[Test Data] Creating minimal test faces...\n');

  for (const identity of identities) {
    const identityDir = path.join(photosDir, identity);
    fs.mkdirSync(identityDir, { recursive: true });

    for (let i = 1; i <= 3; i++) {
      const buffer = createTestFace(identity, i);
      const photoPath = path.join(identityDir, `${i}.jpg`);
      fs.writeFileSync(photoPath, buffer);
      console.log(`  ✅ ${identity}/${i}.jpg`);
    }
  }

  console.log('\n✅ Test faces created (5 identities × 3 photos)');
  console.log('⚠️  These are PLACEHOLDER faces for pipeline testing only.');
  console.log('    Real photos needed for production enrollment.\n');

  // Update consent manifest
  const manifest = {};
  identities.forEach((id, idx) => {
    manifest[id] = {
      full_name: `Test Identity ${idx + 1}`,
      role: 'TEST_DATASET',
      notify_channel: 'none',
      consent_ref: `TEST-PLACEHOLDER-${idx + 1}`,
      consent_at: new Date().toISOString(),
      consent_method: 'test_dataset',
    };
  });

  const manifestPath = path.join(__dirname, 'consent_manifest_test.json');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  console.log(`✅ Manifest saved to consent_manifest_test.json\n`);
}

main().catch(console.error);
