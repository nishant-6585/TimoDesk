/**
 * Purge seed/test identities — SAFELY.
 * Deletes only staff rows that (a) match a known seed name AND (b) have ZERO embeddings,
 * plus any embedding whose consent_ref starts with TEST. Real enrolled people are untouched.
 *
 *   node --env-file=.env scripts/enroll/purge-test-identities.js
 */
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const SEED_NAMES = ['Alice Johnson', 'Bob Smith', 'Charlie Brown', 'Diana Prince', 'Evan Wilson'];

// 1. Delete any TEST-prefixed embeddings (random seed vectors), if any remain.
const { data: testEmbs, error: teErr } = await supabase
  .from('staff_face_embedding')
  .delete()
  .ilike('consent_ref', 'TEST%')
  .select('id');
if (teErr) { console.error('test-embedding delete failed:', teErr.message); process.exit(1); }
console.log(`Deleted ${testEmbs?.length ?? 0} TEST-prefixed embeddings`);

// 2. For each seed name, delete the staff row ONLY if it has zero embeddings.
for (const name of SEED_NAMES) {
  const { data: rows, error } = await supabase.from('staff').select('id').eq('full_name', name);
  if (error) { console.error(`lookup ${name} failed:`, error.message); continue; }
  for (const r of rows || []) {
    const { count, error: cErr } = await supabase
      .from('staff_face_embedding')
      .select('id', { count: 'exact', head: true })
      .eq('staff_id', r.id);
    if (cErr) { console.error(`count for ${name} failed:`, cErr.message); continue; }
    if ((count ?? 0) > 0) {
      console.log(`SKIP ${name} — has ${count} embeddings (not a pure test row)`);
      continue;
    }
    const { error: dErr } = await supabase.from('staff').delete().eq('id', r.id);
    if (dErr) { console.error(`delete ${name} failed:`, dErr.message); continue; }
    console.log(`Deleted test staff: ${name}`);
  }
}
console.log('Purge complete.\n');
