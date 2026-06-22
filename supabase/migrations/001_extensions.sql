-- 001_extensions.sql
-- Enable required PostgreSQL extensions for Mikee
-- Run this first before any tables are created

create extension if not exists "uuid-ossp";
create extension if not exists "vector";

comment on extension "uuid-ossp" is 'UUID generation functions';
comment on extension "vector" is 'pgvector for ML embeddings (face recognition, KB retrieval)';
