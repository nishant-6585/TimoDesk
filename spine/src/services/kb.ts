/**
 * kb.ts — knowledge-base retrieval + ingestion (T5/T6).
 *
 * Thin layer over pgvector: embed text (kb-embedding.ts) and search via the
 * match_kb_chunk RPC (migration 014). Kept separate from the RAG orchestration
 * (rag.ts) so search and ingestion are independently testable.
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { embedText } from './kb-embedding';

export interface KbHit {
  id: string;
  topic: string | null;
  content: string;
  is_faq: boolean;
  similarity: number; // cosine similarity in [0,1], 1 = identical
}

/** pgvector text input format: '[1,2,3]'. supabase-js passes this to the RPC arg. */
function toVectorLiteral(v: number[]): string {
  return '[' + v.join(',') + ']';
}

/**
 * Embed the question and return the nearest KB chunks (newest-first by similarity).
 * @param faqOnly restrict to is_faq rows (the FAQ fast-path)
 */
export async function searchKb(
  supabase: SupabaseClient,
  question: string,
  opts: { limit?: number; faqOnly?: boolean } = {}
): Promise<KbHit[]> {
  const embedding = await embedText(question, 'query');
  const { data, error } = await supabase.rpc('match_kb_chunk', {
    query_embedding: toVectorLiteral(embedding),
    match_count: opts.limit ?? 5,
    faq_only: opts.faqOnly ?? false,
  });
  if (error) throw new Error(`kb search failed: ${error.message}`);
  return (data ?? []) as KbHit[];
}

/**
 * Add (or overwrite) one KB chunk with its embedding. `content` is embedded as a
 * document. Used by the ingestion script and any admin KB-authoring path.
 */
export async function upsertChunk(
  supabase: SupabaseClient,
  chunk: { topic?: string; content: string; is_faq?: boolean; source?: string }
): Promise<void> {
  const embedding = await embedText(chunk.content, 'document');
  const { error } = await supabase.from('kb_chunk').insert({
    topic: chunk.topic ?? null,
    content: chunk.content,
    embedding: toVectorLiteral(embedding),
    is_faq: chunk.is_faq ?? false,
    source: chunk.source ?? 'manual',
  });
  if (error) throw new Error(`kb upsert failed: ${error.message}`);
}

/**
 * Embed every kb_chunk row that has no embedding yet (e.g. the SQL-seeded rows).
 * Returns how many were embedded. Idempotent — re-running only touches new rows.
 */
export async function backfillEmbeddings(supabase: SupabaseClient): Promise<number> {
  const { data: rows, error } = await supabase
    .from('kb_chunk')
    .select('id, content')
    .is('embedding', null);
  if (error) throw new Error(`kb backfill load failed: ${error.message}`);

  let embedded = 0;
  for (const row of rows ?? []) {
    const embedding = await embedText((row as { content: string }).content, 'document');
    const { error: updErr } = await supabase
      .from('kb_chunk')
      .update({ embedding: toVectorLiteral(embedding) })
      .eq('id', (row as { id: string }).id);
    if (updErr) throw new Error(`kb backfill update failed: ${updErr.message}`);
    embedded++;
  }
  return embedded;
}
