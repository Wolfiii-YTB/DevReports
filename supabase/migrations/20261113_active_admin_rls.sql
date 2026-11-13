-- Prevent suspended/rejected administrators from retaining SECURITY DEFINER admin powers.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin' and status = 'active'
  );
$$;

drop policy if exists "admin read all profiles" on public.profiles;
create policy "admin read all profiles" on public.profiles
for select to authenticated
using ((select public.is_admin()) or ((select public.is_active_member()) and status = 'active'));

-- Remove any legacy permissive policy before restoring the intended read boundary.
do $$
declare old_policy record;
begin
  for old_policy in select policyname from pg_policies where schemaname = 'public' and tablename = 'member_sanctions'
  loop execute format('drop policy %I on public.member_sanctions', old_policy.policyname); end loop;
end;
$$;
create policy "admins read member sanctions" on public.member_sanctions
for select to authenticated using ((select public.is_admin()));
create policy "members read own sanctions" on public.member_sanctions
for select to authenticated using (member_id = (select auth.uid()));

create or replace function public.admin_delete_user(target_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare primary_admin uuid;
begin
  if not (select public.is_admin()) or target_user = (select auth.uid()) then
    raise exception 'Action réservée à un administrateur sur un autre compte';
  end if;
  select id into primary_admin from public.profiles where role = 'admin' order by created_at asc limit 1;
  if target_user = primary_admin then
    raise exception 'Le compte administrateur principal ne peut pas être supprimé par un autre membre.';
  end if;
  delete from auth.users where id = target_user;
end;
$$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;
