-- Restrict self-deletion to active members; active admins retain moderation access.
drop policy if exists "authors or admins delete direct messages" on public.team_direct_messages;
create policy "authors or admins delete direct messages" on public.team_direct_messages
for delete to authenticated
using ((select public.is_admin()) or ((select public.is_active_member()) and sender_id = (select auth.uid())));

drop policy if exists "authors or admins delete team messages" on public.team_messages;
create policy "authors or admins delete team messages" on public.team_messages
for delete to authenticated
using ((select public.is_admin()) or ((select public.is_active_member()) and user_id = (select auth.uid())));
