-- 017_tighten_rls.sql
-- Close two holes that RLS-is-enabled hid:
--
--   1. Every policy from 003 was `to authenticated using (true)`. Supabase signups
--      are open by default, so ANY account on this project could read the staff
--      table, face embeddings (biometrics), visitors and conversations. RLS was on;
--      it just wasn't deciding anything. Policies now go through is_admin().
--
--   2. nav_points (011) was `using (true)` with NO role — the `anon` role could
--      read AND write it. That key ships inside the robot APK and the web bundle,
--      so anyone who extracted it could rewrite where the robot drives. The robot
--      and the admin now reach nav_points through the spine (GET/POST/PATCH/DELETE
--      /nav-points, service-role + kiosk/JWT auth), so anon needs nothing here.
--
-- BOOTSTRAP: admin_user is seeded from the accounts that exist right now, so
-- everyone who can log in today keeps working. New signups get NOTHING until a row
-- is added deliberately:
--
--   insert into admin_user (user_id, note)
--   select id, 'granted <date>' from auth.users where email = 'someone@xboom.in';
--
-- On a fresh project auth.users is empty — insert yourself before the first login,
-- or every admin screen comes back empty (that is the fail-closed direction).

-- =============================================================================
-- ADMIN ALLOWLIST
-- =============================================================================

create table if not exists admin_user (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now(),
  note     text
);

comment on table admin_user is
  'Allowlist of Supabase accounts with admin access. Being able to log in is NOT '
  'enough — a row here is what grants data access. Managed with the service role.';

-- Existing accounts keep the access they have today.
insert into admin_user (user_id, note)
select id, 'seeded by migration 017' from auth.users
on conflict (user_id) do nothing;

alter table admin_user enable row level security;

-- security definer so the function can read admin_user while the caller cannot;
-- stable so Postgres evaluates it once per statement, not once per row;
-- search_path pinned so a rogue temp schema can't shadow the table.
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from admin_user where user_id = auth.uid());
$$;

comment on function public.is_admin() is
  'True when the calling user is on the admin allowlist. Used by every RLS policy.';

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Admins may see the allowlist; nobody may edit it over the API (no write policy →
-- only the service role can, which is the spine and the Supabase dashboard).
drop policy if exists "Admins can read admin_user" on admin_user;
create policy "Admins can read admin_user"
  on admin_user for select
  to authenticated
  using (public.is_admin());

-- =============================================================================
-- REPLACE THE `using (true)` POLICIES FROM 003
-- =============================================================================

do $$
declare
  t text;
  p record;
begin
  foreach t in array array[
    'staff', 'staff_face_embedding', 'visitor', 'kb_chunk',
    'capture', 'conversation', 'robot_event', 'patrol_route'
  ]
  loop
    -- Drop whatever 003 (or a later hotfix) left behind, by name.
    for p in select policyname from pg_policies
             where schemaname = 'public' and tablename = t
    loop
      execute format('drop policy %I on %I', p.policyname, t);
    end loop;

    execute format(
      'create policy %I on %I for select to authenticated using (public.is_admin())',
      t || '_select_admin', t);
    execute format(
      'create policy %I on %I for insert to authenticated with check (public.is_admin())',
      t || '_insert_admin', t);
    execute format(
      'create policy %I on %I for update to authenticated using (public.is_admin()) with check (public.is_admin())',
      t || '_update_admin', t);
    execute format(
      'create policy %I on %I for delete to authenticated using (public.is_admin())',
      t || '_delete_admin', t);

    -- Belt and braces: 003 enabled RLS, but a table added later may not have.
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- =============================================================================
-- NAV_POINTS — take `anon` off the table entirely
-- =============================================================================

-- 010 created these for `authenticated`; 011 recreated them with NO role, which
-- silently handed them to anon as well.
drop policy if exists nav_points_select on nav_points;
drop policy if exists nav_points_write  on nav_points;

create policy nav_points_select_admin on nav_points
  for select to authenticated using (public.is_admin());

create policy nav_points_write_admin on nav_points
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

alter table nav_points enable row level security;

-- The spine holds the service role and bypasses all of the above — that is how the
-- robot's chest screen (kiosk token, no Supabase session) still reads and writes
-- nav points after this migration.
