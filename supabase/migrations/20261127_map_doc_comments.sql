-- Admin-only comments on map DevDocs, readable by all active members.
begin;
create table if not exists public.map_doc_comments (
  id uuid primary key default gen_random_uuid(),
  map_doc_id uuid not null references public.map_docs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete restrict,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists map_doc_comments_doc_created_idx
  on public.map_doc_comments(map_doc_id, created_at asc);
alter table public.map_doc_comments enable row level security;
revoke all on table public.map_doc_comments from anon, authenticated;
grant select, insert, delete on table public.map_doc_comments to authenticated;
drop policy if exists "active members read map doc comments" on public.map_doc_comments;
drop policy if exists "admins add map doc comments" on public.map_doc_comments;
drop policy if exists "admins delete map doc comments" on public.map_doc_comments;
create policy "active members read map doc comments" on public.map_doc_comments for select to authenticated
  using ((select public.is_active_member()));
create policy "admins add map doc comments" on public.map_doc_comments for insert to authenticated
  with check ((select public.is_admin()) and user_id = (select auth.uid()));
create policy "admins delete map doc comments" on public.map_doc_comments for delete to authenticated
  using ((select public.is_admin()));
commit;
