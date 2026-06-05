# Timo Supabase Schema

**DPDP-compliant database for the Timo reception robot.**

Includes 7 core tables, Row Level Security, pgvector indexes for ML operations, and nightly retention purge.

## Quick Start

### 1. Run migrations (in order)

Open Supabase Dashboard → **SQL Editor** and run each file:

```
migrations/001_extensions.sql       # Enable uuid-ossp + pgvector
migrations/002_core_tables.sql      # Create all 7 tables
migrations/003_rls_policies.sql     # Row Level Security on every table
migrations/004_indexes.sql          # Indexes for ML + performance
migrations/005_retention_function.sql # DPDP compliance: purge triggers + nightly job
```

**IMPORTANT:** Run them in order (001 → 005). Skipping or reordering will cause errors.

### 2. Load sample KB data

In SQL Editor:

```sql
-- First verify kb_chunk table exists
select count(*) from kb_chunk;

-- Then run seed
\i seed/seed_kb.sql
```

Or copy-paste the contents of `seed/seed_kb.sql` directly.

### 3. Schedule the nightly purge job

In SQL Editor:

```sql
-- Check if pg_cron is enabled (should return 'available')
create extension if not exists "pg_cron";

-- Schedule the nightly purge at 2 AM
select cron.schedule('nightly-purge-timo', '0 2 * * *', 'select purge_expired_data();');

-- Verify it's scheduled
select * from cron.job where jobname = 'nightly-purge-timo';
```

## Schema Overview

### Core Tables

| Table | Purpose | Retention |
|-------|---------|-----------|
| **staff** | xboom team members | Permanent |
| **staff_face_embedding** | Face biometrics (isolated, opt-in only) | Per consent |
| **visitor** | Visitor info (no biometric ever) | 30 days |
| **kb_chunk** | Knowledge base for voice Q&A | Permanent |
| **capture** | Admin snapshots, intrusion frames, patrol recordings | 30d/1y (by type) |
| **conversation** | PII-scrubbed voice transcripts | 7 days |
| **robot_event** | Audit log: all SDK + system events | Permanent |
| **patrol_route** | V2: autonomous patrol waypoints | Permanent |

### Key Privacy Features

✅ **staff_face_embedding is the ONLY biometric table**  
✅ **visitor table NEVER stores biometric data**  
✅ **All personal-data rows have purge_after column**  
✅ **Row Level Security on every table**  
✅ **Nightly automatic purge (DPDP Act compliance)**  
✅ **Consent-gated enrollment (staff only)**  
✅ **Service role (spine) bypasses RLS automatically**  

## Indexes

### Vector Indexes (ML)
- `staff_face_embedding.embedding` — cosine similarity for face matching
- `kb_chunk.embedding` — cosine similarity for semantic KB search

### Performance Indexes
- `robot_event(type, occurred_at)` — dashboard filtering
- `visitor(arrived_at)` — recent visitors
- `capture(taken_at)` — recent captures
- `visitor(purge_after)` — purge query
- `capture(purge_after)` — purge query
- `conversation(purge_after)` — purge query
- `kb_chunk(is_faq)` — FAQ fast-path

## Retention Windows

| Data Type | Retention | Trigger |
|-----------|-----------|---------|
| visitor | 30 days | Auto on insert |
| capture (admin) | 30 days | Auto on insert |
| capture (intrusion) | 365 days | Auto on insert |
| capture (patrol) | 30 days | Auto on insert |
| conversation | 7 days | Auto on insert |
| robot_event | Permanent | Audit log |

**Automatic purge:** Every night at 2 AM, `purge_expired_data()` deletes rows past their retention window and logs the purge to `robot_event` for compliance.

## Testing pgvector

Verify pgvector is working:

```sql
-- Test vector operations
select 
  embedding <-> '[0, 0, 0, 0, 0]'::vector as distance
from staff_face_embedding
limit 1;

-- Test semantic search simulation (dummy vectors for now)
select 
  id, 
  embedding <-> '[0]'::vector as cosine_distance
from kb_chunk
order by cosine_distance
limit 5;
```

## Embeddings

### KB Chunks
- Currently NULL in the seed
- Populated by **voice pipeline** when it runs (future feature)
- Dimension: 1536 (for OpenAI ada-002 or similar)
- Used for semantic FAQ/Q&A retrieval

### Staff Face Embeddings
- Currently empty in seed
- Enrolled per staff member when they opt-in
- Dimension: 512 (for face recognition model)
- Used for visitor face matching

## Row Level Security (RLS)

All tables have RLS enabled. Policies:

- **Authenticated admins** (logged-in users) can read/write all tables
- **Service role** (spine backend) bypasses RLS automatically
- **Public role** (anon) cannot access any table

To verify RLS is on:

```sql
select tablename, rowsecurity 
from pg_tables 
where schemaname = 'public' 
  and tablename in (
    'staff', 'staff_face_embedding', 'visitor', 'kb_chunk', 
    'capture', 'conversation', 'robot_event', 'patrol_route'
  );
```

All should show `rowsecurity = true`.

## Compliance Checklist

✅ DPDP Act: All personal data has `purge_after` and is auto-deleted  
✅ DPDP Act: Visitor table has NO biometric data  
✅ DPDP Act: Consent-gated face enrollment (only staff)  
✅ Privacy: RLS on every table  
✅ Privacy: Service role does not store secrets in code  
✅ Privacy: Conversations are PII-scrubbed before insert  
✅ Audit: All robot events logged to `robot_event`  
✅ Performance: pgvector indexes for ML ops  

## Troubleshooting

### "Extension pgvector not found"
→ Ensure `migrations/001_extensions.sql` ran first.

### "RLS policy missing"
→ Ensure `migrations/003_rls_policies.sql` ran after tables were created.

### Vector index errors
→ Verify dimensions match your embedding model:
  - Face: 512 dims
  - KB text: 1536 dims

### Nightly purge not running
→ Check if pg_cron is enabled and scheduled:
```sql
select * from cron.job;
```

## What's NOT included

❌ **V2 features** (office tour, patrol, intrusion alarm) — deferred to Phase 2  
❌ **Embeddings in seed data** — voice pipeline generates these later  
❌ **Cloud storage integration** — snapshots stored in Supabase Storage separately  
❌ **STT/TTS tables** — those are external services (Deepgram, ElevenLabs)  

## Next Steps

1. **Embeddings**: Voice pipeline will generate + populate them
2. **Auth**: Link `staff.id` to Supabase `auth.users` for admin login
3. **Notifications**: Integrate Slack/WhatsApp for host handoff via `staff.notify_channel`
4. **Storage**: Configure Supabase Storage bucket for snapshot images

---

**xboom · Timo · Land + Air + Water · DPDP-compliant from day one**
