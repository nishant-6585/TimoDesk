-- 003_rls_policies.sql
-- Row Level Security for all tables
-- Authenticated admins can read/write all. Service role (spine) bypasses RLS.

-- Enable RLS on all tables
alter table staff enable row level security;
alter table staff_face_embedding enable row level security;
alter table visitor enable row level security;
alter table kb_chunk enable row level security;
alter table capture enable row level security;
alter table conversation enable row level security;
alter table robot_event enable row level security;
alter table patrol_route enable row level security;

-- =============================================================================
-- STAFF
-- =============================================================================

create policy "Admins can read staff"
  on staff for select
  to authenticated
  using (true);

create policy "Admins can insert staff"
  on staff for insert
  to authenticated
  with check (true);

create policy "Admins can update staff"
  on staff for update
  to authenticated
  using (true);

create policy "Admins can delete staff"
  on staff for delete
  to authenticated
  using (true);

-- =============================================================================
-- STAFF_FACE_EMBEDDING
-- =============================================================================

create policy "Admins can read staff_face_embedding"
  on staff_face_embedding for select
  to authenticated
  using (true);

create policy "Admins can insert staff_face_embedding"
  on staff_face_embedding for insert
  to authenticated
  with check (true);

create policy "Admins can update staff_face_embedding"
  on staff_face_embedding for update
  to authenticated
  using (true);

create policy "Admins can delete staff_face_embedding"
  on staff_face_embedding for delete
  to authenticated
  using (true);

-- =============================================================================
-- VISITOR
-- =============================================================================

create policy "Admins can read visitor"
  on visitor for select
  to authenticated
  using (true);

create policy "Admins can insert visitor"
  on visitor for insert
  to authenticated
  with check (true);

create policy "Admins can update visitor"
  on visitor for update
  to authenticated
  using (true);

create policy "Admins can delete visitor"
  on visitor for delete
  to authenticated
  using (true);

-- =============================================================================
-- KB_CHUNK
-- =============================================================================

create policy "Admins can read kb_chunk"
  on kb_chunk for select
  to authenticated
  using (true);

create policy "Admins can insert kb_chunk"
  on kb_chunk for insert
  to authenticated
  with check (true);

create policy "Admins can update kb_chunk"
  on kb_chunk for update
  to authenticated
  using (true);

create policy "Admins can delete kb_chunk"
  on kb_chunk for delete
  to authenticated
  using (true);

-- =============================================================================
-- CAPTURE
-- =============================================================================

create policy "Admins can read capture"
  on capture for select
  to authenticated
  using (true);

create policy "Admins can insert capture"
  on capture for insert
  to authenticated
  with check (true);

create policy "Admins can update capture"
  on capture for update
  to authenticated
  using (true);

create policy "Admins can delete capture"
  on capture for delete
  to authenticated
  using (true);

-- =============================================================================
-- CONVERSATION
-- =============================================================================

create policy "Admins can read conversation"
  on conversation for select
  to authenticated
  using (true);

create policy "Admins can insert conversation"
  on conversation for insert
  to authenticated
  with check (true);

create policy "Admins can update conversation"
  on conversation for update
  to authenticated
  using (true);

create policy "Admins can delete conversation"
  on conversation for delete
  to authenticated
  using (true);

-- =============================================================================
-- ROBOT_EVENT
-- =============================================================================

create policy "Admins can read robot_event"
  on robot_event for select
  to authenticated
  using (true);

create policy "Admins can insert robot_event"
  on robot_event for insert
  to authenticated
  with check (true);

create policy "Admins can update robot_event"
  on robot_event for update
  to authenticated
  using (true);

create policy "Admins can delete robot_event"
  on robot_event for delete
  to authenticated
  using (true);

-- =============================================================================
-- PATROL_ROUTE
-- =============================================================================

create policy "Admins can read patrol_route"
  on patrol_route for select
  to authenticated
  using (true);

create policy "Admins can insert patrol_route"
  on patrol_route for insert
  to authenticated
  with check (true);

create policy "Admins can update patrol_route"
  on patrol_route for update
  to authenticated
  using (true);

create policy "Admins can delete patrol_route"
  on patrol_route for delete
  to authenticated
  using (true);

-- =============================================================================
-- NOTE: Service role (used by spine) bypasses RLS automatically.
-- No additional policies needed for service role.
-- =============================================================================
