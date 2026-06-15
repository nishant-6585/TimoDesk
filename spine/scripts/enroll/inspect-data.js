/**
 * Read-only inspection of staff + staff_face_embedding.
 * Shows what's real vs test seed data before calibration.
 *
 *   node --env-file=.env scripts/enroll/inspect-data.js
 */
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const { data: staff, error: sErr } = await supabase
  .from('staff')
  .select('id, full_name, phone, person_type, role, created_at')
  .order('created_at', { ascending: true });
if (sErr) { console.error('staff load failed:', sErr.message); process.exit(1); }

const { data: embs, error: eErr } = await supabase
  .from('staff_face_embedding')
  .select('id, staff_id, consent_ref, created_at, embedding');
if (eErr) { console.error('embedding load failed:', eErr.message); process.exit(1); }

// Count embeddings + detect dims + flag test consent_refs per staff
const byStaff = {};
for (const e of embs) {
  const g = (byStaff[e.staff_id] ??= { count: 0, dims: new Set(), testRefs: 0, realRefs: 0 });
  g.count++;
  const vec = typeof e.embedding === 'string' ? JSON.parse(e.embedding) : e.embedding;
  g.dims.add(Array.isArray(vec) ? vec.length : 'non-array');
  if (/^TEST/i.test(e.consent_ref || '')) g.testRefs++; else g.realRefs++;
}

console.log(`\nstaff rows: ${staff.length}   embedding rows: ${embs.length}\n`);
console.log('full_name'.padEnd(22), 'embeds', 'dims', 'testRefs', 'realRefs', 'person_type');
console.log('-'.repeat(80));
for (const s of staff) {
  const g = byStaff[s.id] || { count: 0, dims: new Set(), testRefs: 0, realRefs: 0 };
  console.log(
    (s.full_name || '(null)').padEnd(22),
    String(g.count).padEnd(6),
    [...g.dims].join(',').padEnd(4),
    String(g.testRefs).padEnd(8),
    String(g.realRefs).padEnd(8),
    s.person_type || '(null)'
  );
}

// Orphan embeddings (staff_id not in staff table)
const staffIds = new Set(staff.map(s => s.id));
const orphans = embs.filter(e => !staffIds.has(e.staff_id));
if (orphans.length) console.log(`\n⚠ ${orphans.length} orphan embeddings (no matching staff row)`);

// Distinct consent_ref prefixes
const prefixes = {};
for (const e of embs) {
  const p = (e.consent_ref || '(null)').slice(0, 12);
  prefixes[p] = (prefixes[p] || 0) + 1;
}
console.log('\nconsent_ref prefixes (first 12 chars):');
for (const [p, c] of Object.entries(prefixes)) console.log(`  ${p.padEnd(14)} ${c}`);
console.log('');
