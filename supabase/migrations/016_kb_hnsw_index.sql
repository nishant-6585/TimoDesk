-- 016: replace the IVFFlat KB index with HNSW.
--
-- kb_chunk_vector_idx was created as IVFFlat (lists = 100) by migration 014
-- while kb_chunk was EMPTY. IVFFlat trains its list centroids from the rows
-- present at CREATE INDEX time — trained on nothing, every centroid is
-- degenerate, and with the default ivfflat.probes = 1 a query probes one
-- empty cell and returns ZERO rows (only near-exact self-matches survived).
-- Symptom: /ask always answered "I'll connect you to a team member" even
-- with matching chunks in the KB.
--
-- HNSW builds incrementally per-insert, so it has no empty-table footgun and
-- needs no retraining as the KB grows. Recall/latency are better than IVFFlat
-- at reception-KB scale anyway.
DROP INDEX IF EXISTS kb_chunk_vector_idx;

CREATE INDEX kb_chunk_vector_idx
  ON kb_chunk
  USING hnsw (embedding vector_cosine_ops);

COMMENT ON INDEX kb_chunk_vector_idx IS
  'HNSW cosine index for match_kb_chunk. Replaced IVFFlat (014) which was trained on an empty table and returned zero rows.';
