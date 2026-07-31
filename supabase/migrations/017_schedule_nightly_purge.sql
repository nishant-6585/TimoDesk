-- =============================================================================
-- 017 — Schedule the DPDP nightly purge (pg_cron)
-- =============================================================================
--
-- Migration 005 created purge_expired_data() but left its SCHEDULE as a comment,
-- so whether the purge ever ran depended on somebody pasting SQL into the
-- dashboard. DPDP retention has to be provable from the repo, not from memory —
-- this migration schedules it for real and is idempotent (safe to re-run).
--
-- Runs 02:00 daily (server time — Supabase projects are UTC unless changed).
-- =============================================================================

create extension if not exists pg_cron;

-- Re-registering the same job name would create a DUPLICATE entry rather than
-- replacing it, so drop any existing one first. cron.unschedule throws when the
-- job is absent, hence the guard on cron.job.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'nightly-purge-mikee') then
    perform cron.unschedule('nightly-purge-mikee');
  end if;
end;
$$;

select cron.schedule(
  'nightly-purge-mikee',
  '0 2 * * *',
  $$select purge_expired_data();$$
);

-- Verify with:  select jobname, schedule, active from cron.job;
-- Purge audit trail: select * from robot_event where type = 'retention_purge';
