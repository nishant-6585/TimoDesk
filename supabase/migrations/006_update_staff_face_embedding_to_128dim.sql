-- Migration 006: Update staff_face_embedding vector dimension from 512 to 128
-- Reason: Using @vladmandic/face-api for face detection+alignment+embedding
-- face-api outputs 128-dimensional descriptors with Euclidean distance metric
-- This change affects the IVFFlat index and all matching thresholds

BEGIN;

-- Drop the existing IVFFlat cosine index on the old vector(512) column
DROP INDEX IF EXISTS idx_staff_face_embedding_cosine CASCADE;

-- Alter the embedding column from vector(512) to vector(128)
ALTER TABLE staff_face_embedding
ALTER COLUMN embedding SET DATA TYPE vector(128);

-- Recreate the IVFFlat index for vector(128) with l2 (Euclidean) distance
-- face-api uses Euclidean distance, not cosine
CREATE INDEX idx_staff_face_embedding_l2
ON staff_face_embedding
USING ivfflat (embedding l2_ops)
WITH (lists = 100);

-- Add comments for clarity
COMMENT ON COLUMN staff_face_embedding.embedding IS
  'Face descriptor (128-dim, @vladmandic/face-api). Use Euclidean distance (l2), threshold ~0.5-0.6.';

COMMIT;
