-- 002_core_tables.sql
-- Core tables for Timo reception robot
-- Privacy-first design: no visitor biometric, staff embeddings isolated,
-- retention windows on all personal data

-- Staff: identity for enrolled team members
create table staff (
  id             uuid primary key default gen_random_uuid(),
  full_name      text not null,
  role           text,
  notify_channel text,   -- slack_id / whatsapp / email for host handoff
  active         boolean default true,
  created_at     timestamptz default now()
);

comment on table staff is 'xboom team members; used for face recognition and host handoff';
comment on column staff.notify_channel is 'Notification method: slack_id, whatsapp_phone, or email';

-- Face embeddings: THE ONLY biometric table
-- Isolated from staff identity to allow independent deletion
-- Consent-gated: consent_at timestamp proves opt-in
create table staff_face_embedding (
  id          uuid primary key default gen_random_uuid(),
  staff_id    uuid references staff(id) on delete cascade,
  embedding   vector(512),           -- pgvector; dimension depends on embedding model
  consent_at  timestamptz not null,  -- explicit opt-in timestamp (DPDP requirement)
  consent_ref text,                  -- link/id of signed consent record
  created_at  timestamptz default now()
);

comment on table staff_face_embedding is 'Biometric face vectors for staff. ONLY table with biometric data. Opt-in only. Deletable independently of staff record.';
comment on column staff_face_embedding.consent_at is 'Timestamp when staff member consented to face enrollment (DPDP Act requirement)';

-- Visitors: self-reported details ONLY. NO biometric ever stored.
create table visitor (
  id            uuid primary key default gen_random_uuid(),
  name          text,
  company       text,
  host_staff_id uuid references staff(id) on delete set null,
  purpose       text,
  snapshot_url  text,          -- non-biometric arrival photo (retention-bound)
  arrived_at    timestamptz default now(),
  purge_after   timestamptz    -- DPDP: auto-delete after retention window
);

comment on table visitor is 'Visitor information captured at arrival. Retention-bound. NO biometric stored.';
comment on column visitor.purge_after is 'Automatic purge timestamp (30 days from arrival by default)';

-- Knowledge base: chunked + embedded for RAG voice pipeline
create table kb_chunk (
  id          uuid primary key default gen_random_uuid(),
  topic       text,
  content     text not null,
  embedding   vector(1536),          -- text embedding model dimension
  is_faq      boolean default false, -- true = cached answer for fast-path
  source      text,                  -- 'manual' | 'import' | 'web'
  updated_at  timestamptz default now()
);

comment on table kb_chunk is 'Knowledge base for voice Q&A. Chunks are embedded for semantic search. is_faq=true gets cached in response.';
comment on column kb_chunk.embedding is 'Text embedding (e.g. OpenAI ada-002: 1536 dims). NULL until voice pipeline populates it.';

-- Captures: admin snapshots, intrusion frames, patrol frames
create table capture (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null,   -- 'admin_snapshot' | 'intrusion' | 'patrol'
  storage_url  text not null,
  taken_by     uuid references staff(id) on delete set null,  -- null for autonomous
  taken_at     timestamptz default now(),
  purge_after  timestamptz      -- DPDP: retention window (30d for snapshots, 1y for intrusion)
);

comment on table capture is 'Admin snapshots, intrusion detection frames, patrol recordings. Retention-bound.';
comment on column capture.kind is 'admin_snapshot (30d) | intrusion (1y) | patrol (30d)';

-- Conversations: optional PII-scrubbed transcript log
create table conversation (
  id          uuid primary key default gen_random_uuid(),
  visitor_id  uuid references visitor(id) on delete cascade,
  transcript  jsonb,    -- [{role: 'user'|'assistant', text: '...', ts: ISO8601}]; PII scrubbed before insert
  resolved_by text,     -- 'kb' | 'claude' | 'handoff'
  started_at  timestamptz default now(),
  purge_after timestamptz   -- DPDP: 7 days
);

comment on table conversation is 'Voice conversation transcripts (PII-scrubbed). Short retention (7 days).';
comment on column conversation.transcript is 'JSON array of message objects. Must have PII scrubbed before insert.';

-- Robot events: normalised SDK + system events for audit + ops
create table robot_event (
  id          uuid primary key default gen_random_uuid(),
  type        text not null,
  -- Event types:
  -- admin_session (connected/disconnected)
  -- robot_connection (online/offline)
  -- safety_stop, safety_resume
  -- command_drive, command_head, command_arm
  -- snapshot, face_detected, battery_low
  -- office_hours_blocked, retention_purge
  -- handler_error
  payload     jsonb,
  session_id  text,     -- admin session that triggered it (null for autonomous)
  occurred_at timestamptz default now()
);

comment on table robot_event is 'Audit log: all SDK + system events. Retained indefinitely for compliance.';
comment on column robot_event.type is 'Event type string: admin_session, robot_connection, safety_stop, command_*, snapshot, face_detected, battery_low, office_hours_blocked, handler_error, retention_purge';

-- Patrol routes (V2): ordered waypoints for autonomous patrol
create table patrol_route (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  waypoints   jsonb not null,  -- [{x, y, heading, dwell_s, narration}]
  active_from time,            -- e.g. '19:00' (24h format)
  active_to   time,            -- e.g. '07:00' (24h format)
  enabled     boolean default false,
  created_at  timestamptz default now()
);

comment on table patrol_route is 'V2 feature: autonomous patrol routes with waypoints + narration. Not used in MVP.';
comment on column patrol_route.waypoints is 'JSON array: [{x: float, y: float, heading: float (0-360), dwell_s: int, narration: string}]';
