create table if not exists public.team_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('team_message','direct_message','warning','sanction','announcement','report','task','absence','late')),
  title text not null check (length(trim(title)) between 1 and 120),
  body text not null default '' check (length(body) <= 400),
  target_page text not null default 'dashboard',
  target_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists team_notifications_user_created_idx on public.team_notifications(user_id, created_at desc);
create index if not exists team_notifications_user_unread_idx on public.team_notifications(user_id, read_at, created_at desc);
alter table public.team_notifications enable row level security;
revoke all on public.team_notifications from public, anon, authenticated;
grant select on public.team_notifications to authenticated;
grant update (read_at) on public.team_notifications to authenticated;
drop policy if exists "members read own notifications" on public.team_notifications;
create policy "members read own notifications" on public.team_notifications for select to authenticated
using (user_id = (select auth.uid()) and (select public.is_active_member()));
drop policy if exists "members mark own notifications read" on public.team_notifications;
create policy "members mark own notifications read" on public.team_notifications for update to authenticated
using (user_id = (select auth.uid()) and (select public.is_active_member()))
with check (user_id = (select auth.uid()) and (select public.is_active_member()));

create or replace function public.create_team_notifications()
returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient uuid; new_assignees uuid[]; old_assignees uuid[];
begin
  if tg_table_name = 'team_messages' then
    insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
    select p.id,new.user_id,'team_message','Nouveau message dans le salon',left(trim(new.body),400),'messages',new.id
    from public.profiles p where p.status='active' and p.id<>new.user_id;
  elsif tg_table_name = 'team_direct_messages' then
    insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
    values(new.recipient_id,new.sender_id,'direct_message','Nouveau message privé',left(trim(new.body),400),'messages',new.id);
  elsif tg_table_name = 'member_warnings' then
    insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
    values(new.member_id,new.admin_id,'warning','Nouvel avertissement',left(coalesce(nullif(trim(new.motif),''),'Avertissement')||' · '||coalesce(nullif(trim(new.description),''),trim(new.reason)),400),'dashboard',new.id);
  elsif tg_table_name = 'member_sanctions' then
    if new.action='restore' then return new; end if;
    insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
    values(new.member_id,new.admin_id,'sanction',case when new.action='ban' then 'Bannissement du compte' else 'Suspension du compte' end,left(trim(new.reason),400),'dashboard',new.id);
  elsif tg_table_name = 'team_announcements' then
    if new.active and new.starts_at<=now() and (new.ends_at is null or new.ends_at>now()) then
      insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
      select p.id,new.created_by,'announcement',new.title,left(new.body,400),'dashboard',new.id
      from public.profiles p where p.status='active' and p.id<>new.created_by and (new.recipient_id is null or p.id=new.recipient_id);
    end if;
  elsif tg_table_name = 'reports' then
    insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
    select p.id,new.user_id,'report','Nouveau rapport publié',left(coalesce(nullif(trim(new.title),''),trim(new.project)),400),'reports',new.id
    from public.profiles p where p.role='admin' and p.status='active' and p.id<>new.user_id;
  elsif tg_table_name = 'team_absences' then
    if new.status='pending' then
      insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
      select p.id,new.user_id,'absence','Nouvelle demande d’absence',left(trim(new.reason),400),'presence',new.id
      from public.profiles p where p.role='admin' and p.status='active' and p.id<>new.user_id;
    end if;
  elsif tg_table_name = 'late_notices' then
    if new.status='pending' then
      insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
      select p.id,new.user_id,'late','Nouveau retard signalé',left(trim(new.reason),400),'presence',new.id
      from public.profiles p where p.role='admin' and p.status='active' and p.id<>new.user_id;
    end if;
  elsif tg_table_name = 'tasks' then
    new_assignees:=coalesce(new.assignee_ids,'{}'::uuid[]);
    if tg_op='UPDATE' then old_assignees:=coalesce(old.assignee_ids,'{}'::uuid[]); else old_assignees:='{}'::uuid[]; end if;
    foreach recipient in array new_assignees loop
      if recipient<>new.created_by and not (recipient=any(old_assignees)) then
        insert into public.team_notifications(user_id,actor_id,kind,title,body,target_page,target_id)
        values(recipient,new.created_by,'task','Tâche attribuée : '||left(new.title,80),left(new.description,400),'tasks',new.id);
      end if;
    end loop;
  end if;
  return new;
end;
$$;
revoke all on function public.create_team_notifications() from public, anon, authenticated;

drop trigger if exists notify_team_message on public.team_messages;
create trigger notify_team_message after insert on public.team_messages for each row execute function public.create_team_notifications();
drop trigger if exists notify_direct_message on public.team_direct_messages;
create trigger notify_direct_message after insert on public.team_direct_messages for each row execute function public.create_team_notifications();
drop trigger if exists notify_member_warning on public.member_warnings;
create trigger notify_member_warning after insert on public.member_warnings for each row execute function public.create_team_notifications();
drop trigger if exists notify_member_sanction on public.member_sanctions;
create trigger notify_member_sanction after insert on public.member_sanctions for each row execute function public.create_team_notifications();
drop trigger if exists notify_announcement on public.team_announcements;
create trigger notify_announcement after insert on public.team_announcements for each row execute function public.create_team_notifications();
drop trigger if exists notify_report on public.reports;
create trigger notify_report after insert on public.reports for each row execute function public.create_team_notifications();
drop trigger if exists notify_absence on public.team_absences;
create trigger notify_absence after insert on public.team_absences for each row execute function public.create_team_notifications();
drop trigger if exists notify_late on public.late_notices;
create trigger notify_late after insert on public.late_notices for each row execute function public.create_team_notifications();
drop trigger if exists notify_task_assignment on public.tasks;
create trigger notify_task_assignment after insert or update of assignee_ids on public.tasks for each row execute function public.create_team_notifications();

drop policy if exists "authors or admins delete direct messages" on public.team_direct_messages;
drop policy if exists "admins delete direct messages" on public.team_direct_messages;
create policy "admins delete direct messages" on public.team_direct_messages for delete to authenticated
using ((select public.is_admin()));
drop policy if exists "authors or admins delete team messages" on public.team_messages;
drop policy if exists "admins delete team messages" on public.team_messages;
create policy "admins delete team messages" on public.team_messages for delete to authenticated
using ((select public.is_admin()));

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='team_notifications') then
    execute 'alter publication supabase_realtime add table public.team_notifications';
  end if;
end;
$$;
