-- Migration 014: KB embeddings for the voice brain (T5/T6/T7)
--
-- Two changes to make pgvector retrieval over kb_chunk actually work:
--   1. Re-dimension the embedding column to match the chosen embedding model.
--      Voyage voyage-3.5 outputs 1024-dim vectors (the schema's original 1536
--      assumed OpenAI ada-002). All embeddings are still NULL, so the ALTER is
--      a clean no-data change; the IVFFlat index must be dropped + recreated
--      because it is bound to the column's vector dimension.
--   2. A cosine-similarity search function the spine calls via supabase.rpc(),
--      since supabase-js can't express the pgvector `<=>` operator in a select.

-- 1. Re-dimension (embeddings are NULL, so no data conversion happens).
DROP INDEX IF EXISTS kb_chunk_vector_idx;
ALTER TABLE kb_chunk ALTER COLUMN embedding TYPE vector(1024);

-- Recreate the cosine IVFFlat index at the new dimension.
CREATE INDEX kb_chunk_vector_idx
  ON kb_chunk
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

COMMENT ON COLUMN kb_chunk.embedding IS
  'Text embedding (Voyage voyage-3.5: 1024 dims). NULL until the KB ingestion script populates it. Queries embed with input_type=query, chunks with input_type=document.';

-- 2. Nearest-neighbour search by cosine similarity. Returns similarity in [0,1]
--    (1 = identical) so callers compare against a single intuitive threshold.
--    faq_only restricts to is_faq rows for the sub-2s fast-path (F4).
CREATE OR REPLACE FUNCTION match_kb_chunk(
  query_embedding vector(1024),
  match_count int DEFAULT 5,
  faq_only boolean DEFAULT false
)
RETURNS TABLE (id uuid, topic text, content text, is_faq boolean, similarity float)
LANGUAGE sql STABLE
AS $$
  SELECT
    kb_chunk.id,
    kb_chunk.topic,
    kb_chunk.content,
    kb_chunk.is_faq,
    1 - (kb_chunk.embedding <=> query_embedding) AS similarity
  FROM kb_chunk
  WHERE kb_chunk.embedding IS NOT NULL
    AND (NOT faq_only OR kb_chunk.is_faq = true)
  ORDER BY kb_chunk.embedding <=> query_embedding
  LIMIT match_count;
$$;

COMMENT ON FUNCTION match_kb_chunk IS
  'Cosine nearest-neighbour over kb_chunk. similarity = 1 - cosine_distance. faq_only=true for the FAQ fast-path. Called via supabase.rpc().';
