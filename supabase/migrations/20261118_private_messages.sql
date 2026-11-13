-- Private member-to-member conversations and safe deletion for team chat messages.
create table if not exists public.team_direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  constraint team_direct_messages_distinct_members check (sender_id <> recipient_id)
);

create index if not exists team_direct_messages_sender_idx
  on public.team_direct_messages(sender_id, recipient_id, created_at desc);
create index if not exists team_direct_messages_recipient_idx
  on public.team_direct_messages(recipient_id, sender_id, created_at desc);

alter table public.team_direct_messages enable row level security;
revoke all on table public.team_direct_messages from public, anon, authenticated;
grant select, insert, delete on table public.team_direct_messages to authenticated;

drop policy if exists "participants read direct messages" on public.team_direct_messages;
create policy "participants read direct messages" on public.team_direct_messages
for select to authenticated
using ((select public.is_active_member()) and (sender_id = (select auth.uid()) or recipient_id = (select auth.uid())));

drop policy if exists "active members send direct messages" on public.team_direct_messages;
create policy "active members send direct messages" on public.team_direct_messages
for insert to authenticated
with check (
  (select public.is_active_member())
  and sender_id = (select auth.uid())
  and recipient_id <> (select auth.uid())
  and exists (
    select 1 from public.profiles recipient
    where recipient.id = team_direct_messages.recipient_id and recipient.status = 'active'
  )
);

drop policy if exists "authors or admins delete direct messages" on public.team_direct_messages;
create policy "authors or admins delete direct messages" on public.team_direct_messages
for delete to authenticated
using ((select public.is_admin()) or sender_id = (select auth.uid()));

alter table public.team_messages enable row level security;
revoke all on table public.team_messages from public, anon, authenticated;
grant select, insert, delete on table public.team_messages to authenticated;

drop policy if exists "authors or admins delete team messages" on public.team_messages;
create policy "authors or admins delete team messages" on public.team_messages
for delete to authenticated
using ((select public.is_admin()) or user_id = (select auth.uid()));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_direct_messages'
     ) then
    execute 'alter publication supabase_realtime add table public.team_direct_messages';
  end if;
end;
$$;
