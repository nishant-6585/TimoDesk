/**
 * Seed test embeddings directly into Supabase
 *
 * This bypasses face-api dependency issues and lets us:
 * 1. Test enrollment/recognition pipeline end-to-end
 * 2. Build Part B recognition system
 * 3. Integrate real face detection model later
 *
 * Usage:
 *   node seed-test-embeddings.js
 */

import { createClient } from '@supabase/supabase-js';
import { v4 as uuidv4 } from 'uuid';

// Generate a random 512-dim vector (current schema - will be 128 after migration 006)
function generateEmbedding() {
  const embedding = [];
  for (let i = 0; i < 512; i++) {
    embedding.push(Math.random() * 2 - 1); // Range: -1 to 1
  }
  return embedding;
}

async function seed() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    console.error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
    process.exit(1);
  }

  const supabase = createClient(supabaseUrl, supabaseKey);

  console.log('[Seed] Creating test staff and embeddings...\n');

  const testStaff = [
    {
      id: uuidv4(),
      full_name: 'Alice Johnson',
      role: 'Reception',
      notify_channel: 'slack',
      active: true,
    },
    {
      id: uuidv4(),
      full_name: 'Bob Smith',
      role: 'Manager',
      notify_channel: 'slack',
      active: true,
    },
    {
      id: uuidv4(),
      full_name: 'Charlie Brown',
      role: 'Developer',
      notify_channel: 'slack',
      active: true,
    },
    {
      id: uuidv4(),
      full_name: 'Diana Prince',
      role: 'Designer',
      notify_channel: 'slack',
      active: true,
    },
    {
      id: uuidv4(),
      full_name: 'Evan Wilson',
      role: 'Sales',
      notify_channel: 'slack',
      active: true,
    },
  ];

  // Upsert staff
  for (const staff of testStaff) {
    const { error } = await supabase.from('staff').upsert([staff], { onConflict: 'id' });
    if (error) {
      console.log(`❌ Failed to create ${staff.full_name}: ${error.message}`);
      continue;
    }
    console.log(`✅ ${staff.full_name}`);
  }

  console.log('\nCreating embeddings (3 per staff)...\n');

  let totalEmbeddings = 0;

  // Create 3 embeddings per staff (simulates 3 photos each)
  for (const staff of testStaff) {
    const embeddings = [];

    for (let i = 1; i <= 3; i++) {
      embeddings.push({
        staff_id: staff.id,
        embedding: generateEmbedding(),
        consent_at: new Date().toISOString(),
        consent_ref: `TEST-SEED-${staff.id}-${i}`,
      });
    }

    const { error } = await supabase.from('staff_face_embedding').insert(embeddings);

    if (error) {
      console.log(`❌ Failed to create embeddings for ${staff.full_name}: ${error.message}`);
      continue;
    }

    console.log(`  ✅ ${staff.full_name}: 3 embeddings`);
    totalEmbeddings += 3;
  }

  console.log('\n════════════════════════════════════════════════════════════════');
  console.log('SEEDING COMPLETE');
  console.log('════════════════════════════════════════════════════════════════\n');
  console.log(`✅ Staff: ${testStaff.length}`);
  console.log(`✅ Embeddings: ${totalEmbeddings}`);
  console.log(`\nTest data ready for Part B: Face Recognition Pipeline\n`);
  console.log('Next: Build Part B recognition system + dashboard UI\n');
  console.log('To purge test data before production:');
  console.log(`  psql $DATABASE_URL -c "DELETE FROM staff_face_embedding WHERE consent_ref LIKE 'TEST-SEED-%';"`);
  console.log(`  psql $DATABASE_URL -c "DELETE FROM staff WHERE id LIKE 'test-%';";\n`);
}

seed().catch(err => {
  console.error(`\n❌ Seeding failed: ${err.message}`);
  process.exit(1);
});
