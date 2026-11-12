-- DEVREPORTS — Installation Supabase
-- À exécuter dans Supabase > SQL Editor. Relançable sans recréer les tables.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Membre',
  role text not null default 'developer' check (role in ('developer','admin')),
  roles text[] not null default array['developer']::text[],
  status text not null default 'active' check (status in ('pending','active','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project text not null,
  category text not null,
  version text,
  title text not null,
  work text not null,
  issues text,
  next_steps text,
  author_roles text[] not null default '{}'::text[],
  action_types text[] not null default '{}'::text[],
  report_type text not null default 'progress', platform text, moderation_action text, moderated_user text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.reports enable row level security;
alter table public.profiles add column if not exists status text not null default 'active' check (status in ('pending','active','rejected'));
alter table public.profiles add column if not exists roles text[] not null default array['developer']::text[];
alter table public.reports add column if not exists author_roles text[] not null default '{}'::text[];
alter table public.reports add column if not exists action_types text[] not null default '{}'::text[];
alter table public.reports add column if not exists report_type text not null default 'progress';
alter table public.reports add column if not exists platform text;
alter table public.reports add column if not exists moderation_action text;
alter table public.reports add column if not exists moderated_user text;

create table if not exists public.projects(id uuid primary key default gen_random_uuid(),name text not null unique,active boolean not null default true,created_at timestamptz not null default now());
alter table public.projects enable row level security;
create table if not exists public.report_disputes(id uuid primary key default gen_random_uuid(),report_id uuid not null references public.reports(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,reason text not null,status text not null default 'open',created_at timestamptz not null default now());
alter table public.report_disputes enable row level security;

create table if not exists public.member_warnings (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id),
  reason text not null,
  motif text not null default 'Autre',
  description text not null default '',
  admin_name text not null default '',
  created_at timestamptz not null default now()
);
alter table public.member_warnings add column if not exists motif text not null default 'Autre';
alter table public.member_warnings add column if not exists description text not null default '';
alter table public.member_warnings add column if not exists admin_name text not null default '';
update public.member_warnings set description = reason where description = '' and reason <> '';
update public.member_warnings w set admin_name = p.display_name from public.profiles p where w.admin_id = p.id and w.admin_name = '';
alter table public.member_warnings enable row level security;
create table if not exists public.warning_disputes (
  id uuid primary key default gen_random_uuid(),
  warning_id uuid not null references public.member_warnings(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null,
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at timestamptz not null default now()
);
alter table public.warning_disputes enable row level security;

-- SECURITY DEFINER évite la récursion RLS quand une policy vérifie le rôle.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

create or replace function public.admin_delete_user(target_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not (select public.is_admin()) or target_user = (select auth.uid()) then
    raise exception 'Action réservée à un administrateur sur un autre compte';
  end if;
  delete from auth.users where id = target_user;
end;
$$;
revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
drop policy if exists "admin manage warnings" on public.member_warnings;
create policy "admin manage warnings" on public.member_warnings for all to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "members read own warnings" on public.member_warnings;
create policy "members read own warnings" on public.member_warnings for select to authenticated
using (member_id = (select auth.uid()));
drop policy if exists "read active projects" on public.projects;
create policy "read active projects" on public.projects for select to authenticated using (active or (select public.is_admin()));
drop policy if exists "admin manage projects" on public.projects;
create policy "admin manage projects" on public.projects for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "read report disputes" on public.report_disputes;
create policy "read report disputes" on public.report_disputes for select to authenticated using (user_id=(select auth.uid()) or (select public.is_admin()));

create or replace function public.is_active_member()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and status = 'active');
$$;
revoke all on function public.is_active_member() from public;
grant execute on function public.is_active_member() to authenticated;
drop policy if exists "members read own warning disputes" on public.warning_disputes;
create policy "members read own warning disputes" on public.warning_disputes for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "members contest own warnings" on public.warning_disputes;
create policy "members contest own warnings" on public.warning_disputes for insert to authenticated
with check (user_id = (select auth.uid()) and (select public.is_active_member()) and exists (
  select 1 from public.member_warnings w where w.id = warning_id and w.member_id = (select auth.uid())
));
drop policy if exists "admin manage warning disputes" on public.warning_disputes;
create policy "admin manage warning disputes" on public.warning_disputes for all to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "insert own report disputes" on public.report_disputes;
create policy "insert own report disputes" on public.report_disputes for insert to authenticated with check (user_id=(select auth.uid()) and (select public.is_active_member()));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, role, status)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'Membre'), 'developer', 'pending');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Répare aussi les profils absents si des comptes existaient avant le script.
insert into public.profiles (id, display_name, role)
select id, coalesce(raw_user_meta_data ->> 'display_name', 'Membre'), 'developer'
from auth.users
on conflict (id) do nothing;

-- Le compte administrateur principal est le premier administrateur créé.
update public.profiles set display_name = 'Laélien'
where id = (select id from public.profiles where role = 'admin' order by created_at asc limit 1)
  and display_name <> 'Laélien';
update public.member_warnings set admin_name = 'Laélien'
where admin_id = (select id from public.profiles where role = 'admin' order by created_at asc limit 1);

-- Les rapports embarquent profiles(display_name) dans leurs requêtes PostgREST.
-- Cette FK explicite permet à Supabase de résoudre cette relation.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname = 'reports_user_profile_fkey'
  ) then
    alter table public.reports
      add constraint reports_user_profile_fkey
      foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;
end;
$$;
notify pgrst, 'reload schema';

drop policy if exists "profile read self" on public.profiles;
drop policy if exists "admin read all profiles" on public.profiles;
drop policy if exists "read own reports or admin all" on public.reports;
drop policy if exists "developers insert own reports" on public.reports;
drop policy if exists "developers update own reports or admin" on public.reports;
drop policy if exists "admin delete reports" on public.reports;
drop policy if exists "admin update other profiles" on public.profiles;

create policy "profile read self" on public.profiles
for select to authenticated using (id = (select auth.uid()));
create policy "admin read all profiles" on public.profiles
for select to authenticated using ((select public.is_admin()));
create policy "admin update other profiles" on public.profiles
for update to authenticated using ((select public.is_admin()) and id <> (select auth.uid()))
with check ((select public.is_admin()) and id <> (select auth.uid()));
create policy "read own reports or admin all" on public.reports
for select to authenticated using ((select public.is_admin()) or ((select public.is_active_member()) and user_id = (select auth.uid())));
create policy "developers insert own reports" on public.reports
for insert to authenticated with check ((select public.is_active_member()) and user_id = (select auth.uid()));
create policy "developers update own reports or admin" on public.reports
for update to authenticated
using ((select public.is_admin()) or ((select public.is_active_member()) and user_id = (select auth.uid())))
with check ((select public.is_admin()) or ((select public.is_active_member()) and user_id = (select auth.uid())));
create policy "admin delete reports" on public.reports
for delete to authenticated using ((select public.is_admin()));

-- IMPORTANT : créez d'abord votre compte, puis remplacez l'adresse ci-dessous
-- et exécutez cette requête pour attribuer le rôle administrateur.
-- update public.profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'VOTRE-EMAIL@EXEMPLE.FR');

-- Dans Supabase > Authentication > URL Configuration, ajoutez l'URL du site.
