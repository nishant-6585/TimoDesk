/**
 * Calibration: find the L2 distance threshold that separates same-person from
 * different-person face embeddings, using REAL enrolled data only.
 *
 *   node --env-file=.env scripts/enroll/calibrate.js
 *
 * Computes, with the SAME L2 metric the recognizer uses (see
 * spine/src/services/face-embedding.ts l2Distance):
 *   - self-match  : all embedding pairs from the SAME person (different poses)
 *   - cross-match : all embedding pairs from DIFFERENT people
 * Prints count/min/max/mean/std for each, the gap, and a recommended threshold.
 *
 * TEST rows (consent_ref LIKE 'TEST%') are excluded so random seed vectors can
 * never poison the threshold.
 */
import { createClient } from '@supabase/supabase-js';

// L2 (Euclidean) — identical to l2Distance in services/face-embedding.ts
function l2Distance(a, b) {
  let sum = 0;
  for (let i = 0; i < a.length; i++) {
    const diff = a[i] - b[i];
    sum += diff * diff;
  }
  return Math.sqrt(sum);
}

// pgvector returns the column as a string '[1,2,3]'; supabase-js does not parse it.
function parseEmbedding(raw) {
  if (Array.isArray(raw)) return raw;
  if (typeof raw === 'string') return JSON.parse(raw);
  throw new Error(`unexpected embedding type: ${typeof raw}`);
}

function stats(arr) {
  const n = arr.length;
  if (n === 0) return { n: 0, min: NaN, max: NaN, mean: NaN, std: NaN };
  const min = Math.min(...arr);
  const max = Math.max(...arr);
  const mean = arr.reduce((a, b) => a + b, 0) / n;
  const std = Math.sqrt(arr.reduce((s, d) => s + (d - mean) ** 2, 0) / n);
  return { n, min, max, mean, std };
}

function printStats(label, s) {
  console.log(`${label}`);
  console.log(`  pairs: ${s.n}`);
  console.log(`  min:   ${s.min.toFixed(4)}`);
  console.log(`  mean:  ${s.mean.toFixed(4)}`);
  console.log(`  std:   ${s.std.toFixed(4)}`);
  console.log(`  max:   ${s.max.toFixed(4)}\n`);
}

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set (use --env-file=.env)');
    process.exit(1);
  }
  const supabase = createClient(url, key);

  // Load real embeddings joined to staff names; exclude TEST consent_refs.
  const { data: rows, error } = await supabase
    .from('staff_face_embedding')
    .select('id, staff_id, consent_ref, embedding, staff:staff_id(full_name)');
  if (error) {
    console.error('❌ load failed:', error.message);
    process.exit(1);
  }

  const real = rows.filter(r => !/^TEST/i.test(r.consent_ref || ''));
  console.log(`\nLoaded ${rows.length} embeddings (${real.length} after excluding TEST rows)\n`);

  // Group by staff_id.
  const byStaff = {};
  for (const r of real) {
    const g = (byStaff[r.staff_id] ??= { name: r.staff?.full_name || r.staff_id, vecs: [] });
    g.vecs.push(parseEmbedding(r.embedding));
  }
  const groups = Object.values(byStaff);

  console.log('Per-person embedding counts:');
  for (const g of groups) console.log(`  ${g.name.padEnd(24)} ${g.vecs.length}`);
  console.log('');

  // Dimension sanity.
  const dims = new Set(real.map(r => parseEmbedding(r.embedding).length));
  console.log(`Embedding dims present: ${[...dims].join(', ')}  (expect 128)\n`);

  // Guards.
  const peopleWithPairs = groups.filter(g => g.vecs.length >= 2).length;
  if (groups.length < 2) {
    console.log('⚠ Need at least 2 DIFFERENT people for cross-match. Enroll more, then re-run.');
    process.exit(1);
  }
  if (peopleWithPairs < 1) {
    console.log('⚠ Need at least one person with ≥2 poses for self-match. Enroll multi-pose, then re-run.');
    process.exit(1);
  }

  // Self-match: all within-person pairs.
  const self = [];
  for (const g of groups) {
    for (let i = 0; i < g.vecs.length; i++)
      for (let j = i + 1; j < g.vecs.length; j++)
        self.push(l2Distance(g.vecs[i], g.vecs[j]));
  }

  // Cross-match: all between-person pairs (every embedding of A vs every embedding of B).
  const cross = [];
  for (let a = 0; a < groups.length; a++)
    for (let b = a + 1; b < groups.length; b++)
      for (const va of groups[a].vecs)
        for (const vb of groups[b].vecs)
          cross.push(l2Distance(va, vb));

  const selfS = stats(self);
  const crossS = stats(cross);

  console.log('════════════════════════════════════════════════════════════');
  console.log('DISTRIBUTIONS');
  console.log('════════════════════════════════════════════════════════════\n');
  printStats('SELF-MATCH (same person, different poses):', selfS);
  printStats('CROSS-MATCH (different people):', crossS);

  // Gap analysis.
  const gap = crossS.min - selfS.max;
  const separated = gap > 0;
  const midpoint = (selfS.max + crossS.min) / 2;
  const meanPlus3Std = selfS.mean + 3 * selfS.std;

  console.log('════════════════════════════════════════════════════════════');
  console.log('THRESHOLD');
  console.log('════════════════════════════════════════════════════════════\n');
  console.log(`self-match MAX:  ${selfS.max.toFixed(4)}`);
  console.log(`cross-match MIN: ${crossS.min.toFixed(4)}`);
  console.log(`gap (min-cross − max-self): ${gap.toFixed(4)}  → ${separated ? 'SEPARATED ✅' : 'OVERLAP ❌'}\n`);

  if (!separated) {
    console.log('❌ Distributions OVERLAP — do NOT pick a threshold from this data.');
    console.log('   Recapture cleaner / more varied poses (check the right face was detected) and re-run.\n');
    process.exit(2);
  }

  // Prefer the midpoint of the gap; report the mean+3σ alternative for reference.
  const recommended = midpoint;
  console.log(`midpoint of gap:        ${midpoint.toFixed(4)}   ← recommended`);
  console.log(`self_mean + 3·self_std: ${meanPlus3Std.toFixed(4)}   (reference)\n`);
  console.log(`RECOMMENDED THRESHOLD: ${recommended.toFixed(4)}`);
  console.log(`Round for config: ${recommended.toFixed(2)}\n`);
  console.log('Apply in spine/src/config/face-recognition.ts → FACE_CONFIG.threshold');
  console.log('Rule: L2 < threshold = same person; L2 ≥ threshold = different.\n');
}

main().catch(err => {
  console.error('\n❌ calibration failed:', err.message);
  process.exit(1);
});
