-- DEVREPORTS — Installation Supabase
-- À exécuter dans Supabase > SQL Editor. Relançable sans recréer les tables.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Membre',
  role text not null default 'developer' check (role in ('developer','admin')),
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
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.reports enable row level security;

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

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'Membre'), 'developer');
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

drop policy if exists "profile read self" on public.profiles;
drop policy if exists "admin read all profiles" on public.profiles;
drop policy if exists "read own reports or admin all" on public.reports;
drop policy if exists "developers insert own reports" on public.reports;
drop policy if exists "developers update own reports or admin" on public.reports;
drop policy if exists "admin delete reports" on public.reports;

create policy "profile read self" on public.profiles
for select to authenticated using (id = (select auth.uid()));
create policy "admin read all profiles" on public.profiles
for select to authenticated using ((select public.is_admin()));
create policy "read own reports or admin all" on public.reports
for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "developers insert own reports" on public.reports
for insert to authenticated with check (user_id = (select auth.uid()));
create policy "developers update own reports or admin" on public.reports
for update to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()))
with check (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "admin delete reports" on public.reports
for delete to authenticated using ((select public.is_admin()));

-- IMPORTANT : créez d'abord votre compte, puis remplacez l'adresse ci-dessous
-- et exécutez cette requête pour attribuer le rôle administrateur.
-- update public.profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'VOTRE-EMAIL@EXEMPLE.FR');

-- Dans Supabase > Authentication > URL Configuration, ajoutez l'URL du site.
