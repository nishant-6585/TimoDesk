-- 004_indexes.sql
-- Performance indexes for ML operations and common queries

-- =============================================================================
-- VECTOR INDEXES (for semantic search)
-- =============================================================================

-- pgvector cosine similarity index for face matching
-- Used by face recognition pipeline to find closest staff match
create index staff_face_embedding_vector_idx
  on staff_face_embedding
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

comment on index staff_face_embedding_vector_idx is
  'IVFFlat index for fast cosine similarity search on face embeddings. Used for staff recognition.';

-- pgvector cosine similarity index for KB retrieval
-- Used by voice pipeline for semantic search of KB chunks
create index kb_chunk_vector_idx
  on kb_chunk
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 100);

comment on index kb_chunk_vector_idx is
  'IVFFlat index for fast cosine similarity search on KB embeddings. Used for FAQ/Q&A retrieval.';

-- =============================================================================
-- PERFORMANCE INDEXES (for common queries)
-- =============================================================================

-- Robot event filtering by type and time (for dashboards, audit logs)
create index robot_event_type_time_idx
  on robot_event (type, occurred_at desc);

-- Robot event time-based queries (recent events)
create index robot_event_time_idx
  on robot_event (occurred_at desc);

-- Visitor arrival time (for dashboards showing recent visitors)
create index visitor_arrived_idx
  on visitor (arrived_at desc);

-- Visitor purge queries (for nightly retention job)
create index visitor_purge_idx
  on visitor (purge_after)
  where purge_after is not null;

-- Capture time-based queries
create index capture_time_idx
  on capture (taken_at desc);

-- Capture purge queries
create index capture_purge_idx
  on capture (purge_after)
  where purge_after is not null;

-- Conversation purge queries
create index conversation_purge_idx
  on conversation (purge_after)
  where purge_after is not null;

-- KB FAQ fast-path (for cached responses)
create index kb_chunk_faq_idx
  on kb_chunk (is_faq)
  where is_faq = true;

-- Staff face embedding lookup by staff_id (for updating/deleting)
create index staff_face_embedding_staff_id_idx
  on staff_face_embedding (staff_id);
