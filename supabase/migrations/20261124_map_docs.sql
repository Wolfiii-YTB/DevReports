-- Dedicated design reference library for additions to the game map.
begin;
create table if not exists public.map_docs (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 2 and 140),
  zone text not null default '' check (char_length(zone) <= 100),
  category text not null default 'Autre' check (char_length(category) <= 60),
  description text not null check (char_length(trim(description)) between 3 and 6000),
  reference_url text,
  status text not null default 'idea' check (status in ('idea','approved','building','integrated','rejected')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint map_docs_reference_https check (reference_url is null or reference_url ~ '^https://')
);
create index if not exists map_docs_status_updated_idx on public.map_docs(status, updated_at desc);
alter table public.map_docs enable row level security;
revoke all on table public.map_docs from anon, authenticated;
grant select, insert, update, delete on table public.map_docs to authenticated;
drop policy if exists "active members read map docs" on public.map_docs;
drop policy if exists "admins create map docs" on public.map_docs;
drop policy if exists "admins update map docs" on public.map_docs;
drop policy if exists "admins delete map docs" on public.map_docs;
create policy "active members read map docs" on public.map_docs for select to authenticated
  using ((select public.is_active_member()));
create policy "admins create map docs" on public.map_docs for insert to authenticated
  with check ((select public.is_admin()) and created_by = (select auth.uid()));
create policy "admins update map docs" on public.map_docs for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins delete map docs" on public.map_docs for delete to authenticated
  using ((select public.is_admin()));
commit;
