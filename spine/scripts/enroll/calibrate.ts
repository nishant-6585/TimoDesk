/**
 * Calibration Script: Find optimal L2 distance threshold
 *
 * After enrollment, this script:
 * 1. Measures self-match distances (same person, different photos)
 * 2. Measures cross-match distances (different people)
 * 3. Finds the threshold that best separates them
 *
 * Usage:
 *   npx ts-node calibrate.ts --dataset test  # Calibrate on test data
 *   npx ts-node calibrate.ts --dataset real  # Calibrate on real staff
 */

import { createClient } from '@supabase/supabase-js';

interface EmbeddingRow {
  id: string;
  staff_id: string;
  embedding: number[];
}

// Euclidean L2 distance
function l2Distance(a: number[], b: number[]): number {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const diff = a[i] - b[i];
    sum += diff * diff;
  }
  return Math.sqrt(sum);
}

async function calibrate() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    throw new Error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
  }

  const supabase = createClient(supabaseUrl, supabaseKey);
  const datasetType = process.argv[process.argv.indexOf('--dataset') + 1] || 'test';

  console.log(`[Calibrate] Loading embeddings (${datasetType} dataset)...\n`);

  // Load embeddings
  const { data: embeddings, error: loadError } = await supabase
    .from('staff_face_embedding')
    .select('id, staff_id, embedding')
    .then(res => {
      if (datasetType === 'test') {
        // Filter to test data only
        return {
          data: res.data?.filter(e =>
            (e as any).staff_id.startsWith('test-') ||
            (e as any).staff_id.startsWith('TEST-')
          ),
          error: res.error,
        };
      }
      return res;
    });

  if (loadError || !embeddings) {
    throw new Error(`❌ Failed to load embeddings: ${loadError?.message}`);
  }

  if (embeddings.length === 0) {
    console.log('⚠️  No embeddings found. Run enrollment first.');
    return;
  }

  console.log(`✅ Loaded ${embeddings.length} embeddings\n`);

  // Group by staff_id
  const byStaff: Record<string, EmbeddingRow[]> = {};
  (embeddings as any[]).forEach(e => {
    if (!byStaff[e.staff_id]) byStaff[e.staff_id] = [];
    byStaff[e.staff_id].push({
      id: e.id,
      staff_id: e.staff_id,
      embedding: e.embedding,
    });
  });

  const staffIds = Object.keys(byStaff);
  console.log(`Staff: ${staffIds.length} identities\n`);

  // Measure self-match distances (same person, different photos)
  console.log('📊 SELF-MATCH DISTANCES (same person):');
  const selfMatches: number[] = [];

  staffIds.forEach(staffId => {
    const embeddings = byStaff[staffId];
    if (embeddings.length < 2) return; // Skip if <2 photos

    for (let i = 0; i < embeddings.length; i++) {
      for (let j = i + 1; j < embeddings.length; j++) {
        const dist = l2Distance(embeddings[i].embedding, embeddings[j].embedding);
        selfMatches.push(dist);
      }
    }
  });

  const selfMin = Math.min(...selfMatches);
  const selfMax = Math.max(...selfMatches);
  const selfMean = selfMatches.reduce((a, b) => a + b, 0) / selfMatches.length;
  const selfStd = Math.sqrt(
    selfMatches.reduce((sum, d) => sum + (d - selfMean) ** 2, 0) / selfMatches.length
  );

  console.log(`  Pairs: ${selfMatches.length}`);
  console.log(`  Min: ${selfMin.toFixed(4)}`);
  console.log(`  Mean: ${selfMean.toFixed(4)}`);
  console.log(`  Std: ${selfStd.toFixed(4)}`);
  console.log(`  Max: ${selfMax.toFixed(4)}\n`);

  // Measure cross-match distances (different people)
  console.log('📊 CROSS-MATCH DISTANCES (different people):');
  const crossMatches: number[] = [];

  for (let i = 0; i < staffIds.length; i++) {
    for (let j = i + 1; j < staffIds.length; j++) {
      const staffId1 = staffIds[i];
      const staffId2 = staffIds[j];
      const emb1 = byStaff[staffId1][0]; // Use first photo of each
      const emb2 = byStaff[staffId2][0];

      const dist = l2Distance(emb1.embedding, emb2.embedding);
      crossMatches.push(dist);
    }
  }

  const crossMin = Math.min(...crossMatches);
  const crossMax = Math.max(...crossMatches);
  const crossMean = crossMatches.reduce((a, b) => a + b, 0) / crossMatches.length;
  const crossStd = Math.sqrt(
    crossMatches.reduce((sum, d) => sum + (d - crossMean) ** 2, 0) / crossMatches.length
  );

  console.log(`  Pairs: ${crossMatches.length}`);
  console.log(`  Min: ${crossMin.toFixed(4)}`);
  console.log(`  Mean: ${crossMean.toFixed(4)}`);
  console.log(`  Std: ${crossStd.toFixed(4)}`);
  console.log(`  Max: ${crossMax.toFixed(4)}\n`);

  // Recommend threshold (midpoint + some margin)
  const recommendedThreshold = (selfMax + crossMin) / 2;

  console.log('════════════════════════════════════════════════════════════════');
  console.log('THRESHOLD RECOMMENDATION');
  console.log('════════════════════════════════════════════════════════════════\n');
  console.log(`Separation: self-match MAX (${selfMax.toFixed(4)}) vs cross-match MIN (${crossMin.toFixed(4)})`);
  console.log(`Recommended threshold: ${recommendedThreshold.toFixed(4)}`);
  console.log(`\nTo use this threshold, update spine/src/config/face-recognition.ts:`);
  console.log(`  threshold: ${recommendedThreshold.toFixed(2)}`);
  console.log('\nNote: Distances < threshold = match (same person)');
  console.log('      Distances >= threshold = no match (different people)\n');
}

calibrate().catch(err => {
  console.error(`\n❌ Calibration failed: ${err.message}`);
  process.exit(1);
});
