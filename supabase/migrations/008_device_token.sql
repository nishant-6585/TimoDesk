-- 008_device_token.sql
-- Push-notification device registry (#90 Part B).
-- Per-user infra ONLY — no biometric or visitor PII. Each admin's device(s)
-- register an FCM token so spine can push (visitor arrived, battery low, etc.).

create table device_token (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  token      text not null unique,           -- FCM registration token
  platform   text not null default 'android' check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);

comment on table device_token is 'FCM push tokens per admin user (#90). No biometric/visitor PII — device infra only. Spine (service role) reads these to send pushes.';
comment on column device_token.token is 'FCM registration token; unique so re-registration upserts on conflict.';

create index device_token_user_id_idx on device_token (user_id);

-- RLS: a user can read/write ONLY their own token rows. Spine uses the service
-- role (bypasses RLS) to read all tokens when sending pushes.
alter table device_token enable row level security;

create policy "Users read own device tokens"
  on device_token for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users insert own device tokens"
  on device_token for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Users update own device tokens"
  on device_token for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users delete own device tokens"
  on device_token for delete
  to authenticated
  using (auth.uid() = user_id);
