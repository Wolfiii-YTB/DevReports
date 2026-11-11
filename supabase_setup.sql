-- DEVREPORTS — Installation Supabase
-- À exécuter dans Supabase > SQL Editor.
-- Les nouveaux comptes deviennent développeurs par défaut.
-- Pour promouvoir un compte administrateur, utilisez la requête en bas.

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

-- Crée automatiquement le profil à l'inscription.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', 'Membre'),
    'developer'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Un utilisateur connecté peut lire son profil.
create policy "profile read self" on public.profiles
for select to authenticated
using (id = (select auth.uid()));

-- Les développeurs ne peuvent modifier ni consulter le rôle d'autres personnes.
-- Les administrateurs peuvent lire tous les profils (utile pour l'administration).
create policy "admin read all profiles" on public.profiles
for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

-- Rapports : développeur = ses propres rapports ; admin = tous les rapports.
create policy "read own reports or admin all" on public.reports
for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

create policy "developers insert own reports" on public.reports
for insert to authenticated
with check (user_id = (select auth.uid()));

create policy "developers update own reports or admin" on public.reports
for update to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
)
with check (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

create policy "admin delete reports" on public.reports
for delete to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  )
);

-- IMPORTANT : créez d'abord votre compte depuis le site, puis remplacez l'adresse
-- ci-dessous par votre adresse et exécutez cette requête pour devenir administrateur.
-- update public.profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'VOTRE-EMAIL@EXEMPLE.FR');

-- Dans Supabase > Authentication > URL Configuration, ajoutez l'URL de votre site.
