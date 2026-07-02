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
  console.log('DISTRIBUTIONS (all pairwise — context)');
  console.log('════════════════════════════════════════════════════════════\n');
  printStats('SELF-MATCH (same person, different poses):', selfS);
  printStats('CROSS-MATCH (different people):', crossS);

  // ── Decision metric: leave-one-out nearest-neighbour ──────────────────────
  // This mirrors how the recognizer actually matches: a query face is compared
  // to each person's CLOSEST enrolled pose, not to all pairs. We treat every
  // enrolled embedding as a held-out query and find its nearest genuine
  // (same-person) and nearest impostor (other-person) neighbour.
  const flat = [];
  for (const g of groups) for (const v of g.vecs) flat.push({ name: g.name, v });

  const genuine = [];
  const impostor = [];
  let rank1Correct = 0;
  // Per-person worst (max) genuine NN — how loosely a person's own poses cohere.
  const worstSelfByName = {};
  // The single closest impostor pair anywhere — the collision that caps precision.
  let closestImpostor = { a: null, b: null, d: Infinity };
  for (let i = 0; i < flat.length; i++) {
    let gMin = Infinity;
    let iMin = Infinity;
    let iMinName = null;
    for (let j = 0; j < flat.length; j++) {
      if (i === j) continue;
      const d = l2Distance(flat[i].v, flat[j].v);
      if (flat[i].name === flat[j].name) {
        gMin = Math.min(gMin, d);
      } else if (d < iMin) {
        iMin = d;
        iMinName = flat[j].name;
      }
    }
    genuine.push(gMin);
    impostor.push(iMin);
    if (gMin < iMin) rank1Correct++;
    if (Number.isFinite(gMin))
      worstSelfByName[flat[i].name] = Math.max(worstSelfByName[flat[i].name] ?? 0, gMin);
    if (iMin < closestImpostor.d) closestImpostor = { a: flat[i].name, b: iMinName, d: iMin };
  }
  const genS = stats(genuine);
  const impS = stats(impostor);

  console.log('════════════════════════════════════════════════════════════');
  console.log('DECISION METRIC: nearest-neighbour (leave-one-out)');
  console.log('════════════════════════════════════════════════════════════\n');
  printStats('GENUINE  (nearest SAME-person pose):', genS);
  printStats('IMPOSTOR (nearest OTHER-person pose):', impS);
  console.log(
    `rank-1 accuracy: ${rank1Correct}/${flat.length} = ${((100 * rank1Correct) / flat.length).toFixed(0)}%\n`
  );

  const nnGap = impS.min - genS.max;
  const nnSeparated = nnGap > 0;

  // ── Per-person enrollment health + re-enrollment worklist ─────────────────
  // Turns "recapture the loosest enrollment" into an explicit list. Two flags:
  //   THIN  — fewer than MIN_POSES poses (weak coverage of angles/lighting).
  //   LOOSE — this person's own poses are as far apart as the closest impostor,
  //           i.e. their worst self-distance ≥ impostor.min (they blur the gap).
  const MIN_POSES = 5;
  console.log('════════════════════════════════════════════════════════════');
  console.log('ENROLLMENT HEALTH (who to re-capture)');
  console.log('════════════════════════════════════════════════════════════\n');
  console.log(`  ${'person'.padEnd(24)} ${'poses'.padEnd(6)} ${'worst-self'.padEnd(11)} flags`);
  const reEnroll = new Set();
  for (const g of [...groups].sort((x, y) => (worstSelfByName[y.name] ?? 0) - (worstSelfByName[x.name] ?? 0))) {
    const poses = g.vecs.length;
    const worst = worstSelfByName[g.name];
    const thin = poses < MIN_POSES;
    const loose = Number.isFinite(worst) && worst >= impS.min;
    const flags = [thin ? 'THIN' : '', loose ? 'LOOSE' : ''].filter(Boolean).join(',') || 'ok';
    if (thin || loose) reEnroll.add(g.name);
    const worstStr = Number.isFinite(worst) ? worst.toFixed(4) : '  —  ';
    console.log(`  ${g.name.padEnd(24)} ${String(poses).padEnd(6)} ${worstStr.padEnd(11)} ${flags}`);
  }
  console.log('');
  if (closestImpostor.a) {
    console.log(
      `Closest impostor pair: ${closestImpostor.a} ↔ ${closestImpostor.b} @ ${closestImpostor.d.toFixed(4)}`
    );
    // The two people in the closest collision are always worth re-capturing sharper.
    reEnroll.add(closestImpostor.a);
    reEnroll.add(closestImpostor.b);
  }
  if (reEnroll.size) {
    console.log(`\n👉 Re-enroll (sharper, more frontal, ≥${MIN_POSES} poses): ${[...reEnroll].join(', ')}`);
    console.log('   Then re-run this script — the goal is a POSITIVE gap so the threshold has room.\n');
  } else {
    console.log('\n✅ All enrollments look healthy (enough poses, tight self-distance).\n');
  }

  console.log('════════════════════════════════════════════════════════════');
  console.log('THRESHOLD');
  console.log('════════════════════════════════════════════════════════════\n');
  console.log(`genuine  MAX: ${genS.max.toFixed(4)}`);
  console.log(`impostor MIN: ${impS.min.toFixed(4)}`);
  console.log(`gap (impostor.min − genuine.max): ${nnGap.toFixed(4)}  → ${nnSeparated ? 'SEPARATED ✅' : 'OVERLAP ❌'}\n`);

  if (!nnSeparated) {
    // Overlapping: no threshold cleanly separates. Recommend the PRECISION choice
    // (just below the closest impostor) so we never emit a wrong name — the same
    // trade-off currently in the config. The margin guard + voting cover the rest.
    const precision = Math.floor((impS.min - 0.001) * 100) / 100; // 2dp, just below impostor.min
    console.log('❌ Distributions OVERLAP — a global threshold cannot cleanly separate.');
    console.log('   Fix the enrollments above to open a positive gap. Meanwhile, for PRECISION');
    console.log(`   (reject the collision → occasional "unknown" over a wrong name), set:`);
    console.log(`     FACE_CONFIG.threshold = ${precision.toFixed(2)}   (just below impostor.min ${impS.min.toFixed(4)})`);
    console.log('   Keep the margin guard + temporal voting on — they carry the overlap.\n');
    process.exit(2);
  }

  // Separated: threshold sits in the gap between worst genuine and closest impostor.
  const recommended = (genS.max + impS.min) / 2;
  console.log(`RECOMMENDED THRESHOLD (gap midpoint): ${recommended.toFixed(4)}`);
  console.log(`Round for config: ${recommended.toFixed(2)}\n`);
  console.log('Recognizer rule (nearest-neighbour):');
  console.log('  • compute query embedding, find nearest enrolled embedding across all staff');
  console.log('  • nearest distance <  threshold → match that person');
  console.log('  • nearest distance ≥  threshold → unknown / visitor');
  console.log('Apply in spine/src/config/face-recognition.ts → FACE_CONFIG.threshold\n');
}

main().catch(err => {
  console.error('\n❌ calibration failed:', err.message);
  process.exit(1);
});
