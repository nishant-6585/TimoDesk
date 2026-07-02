/**
 * KB ingestion: embed knowledge-base chunks so the voice brain can retrieve them.
 *
 *   node --env-file=.env scripts/kb/ingest.js            # embed rows missing an embedding
 *   node --env-file=.env scripts/kb/ingest.js kb.json    # + insert chunks from a JSON file first
 *
 * kb.json format: [{ "topic": "...", "content": "...", "is_faq": true }, ...]
 *
 * Uses Voyage voyage-3.5 (1024-dim, input_type=document) — the SAME provider and
 * dimension as spine/src/services/kb-embedding.ts. Idempotent: only embeds rows
 * whose embedding is NULL, so re-running is safe.
 */
import { readFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const MODEL = process.env.VOYAGE_MODEL || 'voyage-3.5';
const DIM = 1024;

async function embed(text, inputType) {
  const key = process.env.VOYAGE_API_KEY;
  if (!key) throw new Error('VOYAGE_API_KEY not set (use --env-file=.env)');
  const resp = await fetch('https://api.voyageai.com/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ input: text, model: MODEL, input_type: inputType, output_dimension: DIM }),
  });
  if (!resp.ok) throw new Error(`voyage ${resp.status}: ${await resp.text().catch(() => '')}`);
  const { data } = await resp.json();
  const v = data?.[0]?.embedding;
  if (!v || v.length !== DIM) throw new Error(`expected ${DIM} dims, got ${v?.length}`);
  return '[' + v.join(',') + ']';
}

async function main() {
  const url = process.env.SUPABASE_URL;
  const svcKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !svcKey) {
    console.error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set (--env-file=.env)');
    process.exit(1);
  }
  const supabase = createClient(url, svcKey);

  // Optional: insert new chunks from a JSON file before embedding.
  const file = process.argv[2];
  if (file) {
    const chunks = JSON.parse(readFileSync(file, 'utf8'));
    console.log(`Inserting ${chunks.length} chunks from ${file}...`);
    for (const c of chunks) {
      if (!c.content) continue;
      const embedding = await embed(c.content, 'document');
      const { error } = await supabase.from('kb_chunk').insert({
        topic: c.topic ?? null,
        content: c.content,
        embedding,
        is_faq: c.is_faq ?? false,
        source: c.source ?? 'import',
      });
      if (error) throw new Error(`insert failed: ${error.message}`);
    }
    console.log('  inserted + embedded.\n');
  }

  // Backfill: embed every row that still has a NULL embedding (e.g. SQL-seeded rows).
  const { data: rows, error } = await supabase
    .from('kb_chunk')
    .select('id, topic, content')
    .is('embedding', null);
  if (error) throw new Error(`load failed: ${error.message}`);

  console.log(`Embedding ${rows.length} chunk(s) with NULL embedding...`);
  let done = 0;
  for (const row of rows) {
    const embedding = await embed(row.content, 'document');
    const { error: updErr } = await supabase.from('kb_chunk').update({ embedding }).eq('id', row.id);
    if (updErr) throw new Error(`update failed for ${row.id}: ${updErr.message}`);
    done++;
    console.log(`  [${done}/${rows.length}] ${row.topic || row.id}`);
  }
  console.log(`\n✅ Embedded ${done} chunk(s). KB is ready for retrieval.`);
}

main().catch(err => {
  console.error('\n❌ ingestion failed:', err.message);
  process.exit(1);
});
