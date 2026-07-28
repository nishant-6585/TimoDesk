-- 015: re-assert match_kb_chunk WITHOUT a similarity threshold.
--
-- The deployed function (hand-applied before CLI history was repaired)
-- filtered rows by a minimum similarity, so real questions (~0.5-0.7 cosine
-- similarity) returned zero rows and the voice brain always answered
-- "I'll connect you to a team member". Ranking/threshold decisions belong in
-- the spine (rag.ts FAQ_FAST_PATH_THRESHOLD / LOCAL_MISS_THRESHOLD), not in
-- the database: the RPC returns the top-N nearest chunks unconditionally.
DROP FUNCTION IF EXISTS match_kb_chunk(vector, int, boolean);
DROP FUNCTION IF EXISTS match_kb_chunk(vector, float, int, boolean);

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
  'Cosine nearest-neighbour over kb_chunk, NO similarity threshold — thresholds live in the spine. similarity = 1 - cosine_distance. faq_only=true for the FAQ fast-path. Called via supabase.rpc().';
