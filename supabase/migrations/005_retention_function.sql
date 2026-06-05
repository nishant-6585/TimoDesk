-- 005_retention_function.sql
-- DPDP Act compliance: nightly purge of expired personal data
-- Deletes rows where purge_after < now()

create or replace function purge_expired_data()
returns void
language plpgsql
security definer
as $$
declare
  deleted_visitors int;
  deleted_captures int;
  deleted_conversations int;
begin
  -- Delete expired visitors (and their snapshots)
  -- Cascade: associated conversations are also deleted
  delete from visitor where purge_after < now();
  get diagnostics deleted_visitors = row_count;

  -- Delete expired captures (intrusion frames, admin snapshots, patrol frames)
  delete from capture where purge_after < now();
  get diagnostics deleted_captures = row_count;

  -- Delete expired conversations (PII-scrubbed transcripts)
  delete from conversation where purge_after < now();
  get diagnostics deleted_conversations = row_count;

  -- Log the purge run to robot_event for compliance audit
  insert into robot_event (type, payload)
  values ('retention_purge', jsonb_build_object(
    'deleted_visitors', deleted_visitors,
    'deleted_captures', deleted_captures,
    'deleted_conversations', deleted_conversations,
    'ran_at', now(),
    'reason', 'DPDP Act compliance: purge_after expired'
  ));
end;
$$;

comment on function purge_expired_data() is
  'DPDP compliance: deletes all visitor, capture, and conversation rows past their retention window. Logs purge event. Call nightly via pg_cron.';

-- =============================================================================
-- PURGE SCHEDULING (for Supabase pg_cron)
-- =============================================================================
--
-- To enable the nightly purge, run this in Supabase Dashboard → SQL Editor:
--
--   select cron.schedule('nightly-purge-timo', '0 2 * * *', 'select purge_expired_data();');
--
-- This runs at 2:00 AM every day.
-- To verify it's scheduled:
--
--   select * from cron.job;
--
-- To remove:
--
--   select cron.unschedule('nightly-purge-timo');
--
-- =============================================================================

-- =============================================================================
-- HELPER FUNCTION: Set purge_after on visitor insert
-- =============================================================================
--
-- Trigger to auto-set purge_after on visitor insert (30 days):
--
create or replace function set_visitor_purge_after()
returns trigger
language plpgsql
as $$
begin
  new.purge_after := now() + interval '30 days';
  return new;
end;
$$;

create trigger visitor_set_purge_after
  before insert on visitor
  for each row
  execute function set_visitor_purge_after();

comment on trigger visitor_set_purge_after on visitor is
  'Auto-set purge_after to now() + 30 days on visitor insert (DPDP compliance)';

-- =============================================================================
-- HELPER FUNCTION: Set purge_after on capture insert
-- =============================================================================
--
-- Trigger to auto-set purge_after on capture insert:
-- - admin_snapshot: 30 days
-- - intrusion: 1 year
-- - patrol: 30 days
--
create or replace function set_capture_purge_after()
returns trigger
language plpgsql
as $$
declare
  retention_days int;
begin
  if new.kind = 'intrusion' then
    retention_days := 365;
  else
    retention_days := 30;  -- admin_snapshot, patrol
  end if;

  new.purge_after := now() + (retention_days || ' days')::interval;
  return new;
end;
$$;

create trigger capture_set_purge_after
  before insert on capture
  for each row
  execute function set_capture_purge_after();

comment on trigger capture_set_purge_after on capture is
  'Auto-set purge_after based on kind: intrusion=365d, others=30d (DPDP compliance)';

-- =============================================================================
-- HELPER FUNCTION: Set purge_after on conversation insert
-- =============================================================================
--
-- Trigger to auto-set purge_after on conversation insert (7 days):
--
create or replace function set_conversation_purge_after()
returns trigger
language plpgsql
as $$
begin
  new.purge_after := now() + interval '7 days';
  return new;
end;
$$;

create trigger conversation_set_purge_after
  before insert on conversation
  for each row
  execute function set_conversation_purge_after();

comment on trigger conversation_set_purge_after on conversation is
  'Auto-set purge_after to now() + 7 days on conversation insert (DPDP compliance, PII scrubbed)';
