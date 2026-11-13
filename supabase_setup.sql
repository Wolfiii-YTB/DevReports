RESET ROLE;

-- DEVREPORTS — Installation Supabase
-- À exécuter dans Supabase > SQL Editor. Relançable sans recréer les tables.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Membre',
  nickname text not null default '',
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
  discord_server text, discord_area text, discord_target text, discord_changes text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.reports enable row level security;
alter table public.profiles add column if not exists status text not null default 'active' check (status in ('pending','active','rejected'));
alter table public.profiles add column if not exists roles text[] not null default array['developer']::text[];
alter table public.profiles add column if not exists nickname text not null default '';
alter table public.profiles add column if not exists suspended_until timestamptz;
alter table public.profiles add column if not exists restriction_reason text not null default '';
alter table public.profiles drop constraint if exists profiles_status_check;
alter table public.profiles add constraint profiles_status_check check (status in ('pending','active','rejected','suspended','banned'));
alter table public.reports add column if not exists author_roles text[] not null default '{}'::text[];
alter table public.reports add column if not exists action_types text[] not null default '{}'::text[];
alter table public.reports add column if not exists report_type text not null default 'progress';
alter table public.reports add column if not exists platform text;
alter table public.reports add column if not exists moderation_action text;
alter table public.reports add column if not exists moderated_user text;
alter table public.reports add column if not exists discord_server text;
alter table public.reports add column if not exists discord_area text;
alter table public.reports add column if not exists discord_target text;
alter table public.reports add column if not exists discord_changes text;

create table if not exists public.projects(id uuid primary key default gen_random_uuid(),name text not null unique,active boolean not null default true,created_at timestamptz not null default now());
alter table public.projects enable row level security;
create table if not exists public.team_roles (
  role_key text primary key check (role_key ~ '^[a-z][a-z0-9_]{1,39}$'),
  label text not null check (length(trim(label)) between 2 and 50),
  created_at timestamptz not null default now()
);
alter table public.team_roles enable row level security;
insert into public.team_roles(role_key,label) values
  ('developer','Développeur'),('scripter','Scripteur'),('builder','Constructeur / Builder'),
  ('ui_ux','UI / UX Designer'),('modeler','Modeleur 3D'),('animator','Animateur'),
  ('sound_designer','Audio / effets'),('tester_qa','Testeur QA'),('graphic_designer','Graphiste'),
  ('translator','Traducteur'),('moderator','Modérateur'),('administrator','Admin serveur'),
  ('discord_admin','Admin Discord'),('staff','Staff'),('community','Communauté'),
  ('community_manager','Community Manager'),('support','Support'),('event_manager','Organisateur d’événements')
on conflict (role_key) do nothing;
-- Retire l’ancien rôle générique « Communauté » ; les fonctions concrètes restent configurables.
update public.profiles set roles = array_remove(roles,'community');
update public.reports set author_roles = array_remove(author_roles,'community');
delete from public.team_roles where role_key='community';
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
create table if not exists public.member_sanctions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id),
  action text not null check (action in ('suspend','ban','restore')),
  reason text not null,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.member_sanctions enable row level security;
create table if not exists public.sanction_disputes (
  id uuid primary key default gen_random_uuid(),
  sanction_id uuid not null references public.member_sanctions(id) on delete cascade,
  member_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (length(trim(reason)) between 3 and 3000),
  status text not null default 'open' check (status in ('open','reviewed','accepted','dismissed')),
  admin_note text not null default '',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.sanction_disputes enable row level security;
create unique index if not exists one_open_sanction_dispute_per_member
  on public.sanction_disputes(sanction_id,member_id) where status='open';
create index if not exists sanction_disputes_created_idx on public.sanction_disputes(created_at desc);
revoke all on table public.member_sanctions from anon, authenticated;
grant select on table public.member_sanctions to authenticated;
revoke all on table public.sanction_disputes from anon, authenticated;
grant select, insert, update on table public.sanction_disputes to authenticated;

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

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 2 and 140),
  description text not null default '',
  status text not null default 'todo' check (status in ('backlog','todo','doing','review','done')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  position bigint not null default 0,
  project text not null default '',
  assigned_to uuid references public.profiles(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  due_date date,
  labels text[] not null default '{}'::text[],
  checklist jsonb not null default '[]'::jsonb check (jsonb_typeof(checklist) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.tasks add column if not exists position bigint not null default 0;
alter table public.tasks add column if not exists assignee_ids uuid[] not null default '{}'::uuid[];
update public.tasks set assignee_ids=array[assigned_to]::uuid[] where assigned_to is not null and cardinality(assignee_ids)=0;
create index if not exists tasks_assignee_ids_idx on public.tasks using gin(assignee_ids);
alter table public.tasks enable row level security;

create table if not exists public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.task_comments enable row level security;

create table if not exists public.team_absences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text not null check (length(trim(reason)) between 3 and 2000),
  status text not null default 'pending' check (status in ('pending','approved','rejected','recorded')),
  absence_kind text not null default 'planned' check (absence_kind in ('planned','unjustified')),
  recorded_by uuid references public.profiles(id) on delete set null,
  admin_note text not null default '',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);
alter table public.team_absences add column if not exists absence_kind text not null default 'planned';
alter table public.team_absences add column if not exists recorded_by uuid references public.profiles(id) on delete set null;
alter table public.team_absences drop constraint if exists team_absences_status_check;
alter table public.team_absences add constraint team_absences_status_check check (status in ('pending','approved','rejected','recorded'));
alter table public.team_absences drop constraint if exists team_absences_absence_kind_check;
alter table public.team_absences add constraint team_absences_absence_kind_check check (absence_kind in ('planned','unjustified'));
alter table public.team_absences enable row level security;

create table if not exists public.late_notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  session_at timestamptz not null,
  expected_delay_minutes integer not null check (expected_delay_minutes between 1 and 1440),
  reason text not null check (length(trim(reason)) between 3 and 2000),
  status text not null default 'pending' check (status in ('pending','acknowledged','recorded')),
  late_kind text not null default 'reported' check (late_kind in ('reported','justified','unjustified')),
  recorded_by uuid references public.profiles(id) on delete set null,
  admin_note text not null default '',
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.late_notices add column if not exists late_kind text not null default 'reported';
alter table public.late_notices add column if not exists recorded_by uuid references public.profiles(id) on delete set null;
alter table public.late_notices drop constraint if exists late_notices_status_check;
alter table public.late_notices add constraint late_notices_status_check check (status in ('pending','acknowledged','recorded'));
alter table public.late_notices drop constraint if exists late_notices_late_kind_check;
alter table public.late_notices add constraint late_notices_late_kind_check check (late_kind in ('reported','justified','unjustified'));
alter table public.late_notices enable row level security;

create table if not exists public.team_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 2 and 120),
  body text not null check (length(trim(body)) between 2 and 4000),
  recipient_id uuid references public.profiles(id) on delete cascade,
  display_home boolean not null default true,
  display_banner boolean not null default false,
  active boolean not null default true,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (display_home or display_banner),
  check (ends_at is null or ends_at > starts_at)
);
alter table public.team_announcements enable row level security;

create table if not exists public.team_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table public.team_messages enable row level security;

create table if not exists public.team_direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  constraint team_direct_messages_distinct_members check (sender_id <> recipient_id)
);
alter table public.team_direct_messages enable row level security;

create index if not exists tasks_board_idx on public.tasks(status, updated_at desc);
create index if not exists tasks_assignee_idx on public.tasks(assigned_to, status);
create index if not exists tasks_creator_idx on public.tasks(created_by, created_at desc);
create index if not exists task_comments_task_created_idx on public.task_comments(task_id, created_at);
create index if not exists team_absences_member_created_idx on public.team_absences(user_id, created_at desc);
create index if not exists team_absences_status_dates_idx on public.team_absences(status, start_date, end_date);
create index if not exists late_notices_member_created_idx on public.late_notices(user_id, created_at desc);
create index if not exists late_notices_status_created_idx on public.late_notices(status, created_at desc);
create index if not exists team_announcements_active_created_idx on public.team_announcements(active, starts_at, ends_at, created_at desc);
create index if not exists team_messages_created_idx on public.team_messages(created_at desc);
create index if not exists team_direct_messages_sender_idx on public.team_direct_messages(sender_id,recipient_id,created_at desc);
create index if not exists team_direct_messages_recipient_idx on public.team_direct_messages(recipient_id,sender_id,created_at desc);

create index if not exists reports_user_created_idx on public.reports(user_id, created_at desc);
create index if not exists reports_created_idx on public.reports(created_at desc);
create index if not exists profiles_status_idx on public.profiles(status);
create index if not exists member_warnings_member_created_idx on public.member_warnings(member_id, created_at desc);
create index if not exists warning_disputes_status_created_idx on public.warning_disputes(status, created_at desc);
create index if not exists report_disputes_user_created_idx on public.report_disputes(user_id, created_at desc);

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
    where id = (select auth.uid()) and role = 'admin' and status = 'active'
  );
$$;

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

create or replace function public.admin_delete_team_role(target_role text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not (select public.is_admin()) then
    raise exception 'Action réservée à un administrateur';
  end if;
  if not exists (select 1 from public.team_roles where role_key = target_role) then
    raise exception 'Rôle introuvable';
  end if;
  update public.profiles
  set roles = array_remove(roles, target_role)
  where roles @> array[target_role];
  delete from public.team_roles where role_key = target_role;
end;
$$;
revoke all on function public.admin_delete_team_role(text) from public;
grant execute on function public.admin_delete_team_role(text) to authenticated;

create or replace function public.admin_set_member_roles(target_user uuid, target_roles text[])
returns void language plpgsql security definer set search_path = '' as $$
declare primary_admin uuid;
begin
  if not (select public.is_admin()) then raise exception 'Action réservée à un administrateur.'; end if;
  select id into primary_admin from public.profiles where role='admin' order by created_at asc limit 1;
  if target_user = (select auth.uid()) and target_user <> primary_admin then
    raise exception 'Seul le compte administrateur principal peut modifier ses propres rôles.';
  end if;
  if target_user = primary_admin and (select auth.uid()) <> primary_admin then
    raise exception 'Seul le compte administrateur principal peut modifier ses propres rôles.';
  end if;
  if not exists(select 1 from public.profiles where id=target_user) then raise exception 'Membre introuvable.'; end if;
  if exists(select 1 from unnest(coalesce(target_roles,'{}'::text[])) as selected(role_key) where not exists(select 1 from public.team_roles r where r.role_key=selected.role_key)) then
    raise exception 'Un des rôles sélectionnés n’existe plus.';
  end if;
  update public.profiles set roles=(select coalesce(array_agg(distinct selected.role_key order by selected.role_key),'{}'::text[]) from unnest(coalesce(target_roles,'{}'::text[])) as selected(role_key)) where id=target_user;
end;
$$;
revoke all on function public.admin_set_member_roles(uuid,text[]) from public;
grant execute on function public.admin_set_member_roles(uuid,text[]) to authenticated;

create or replace function public.guard_primary_admin_roles()
returns trigger language plpgsql security definer set search_path = '' as $$
declare primary_admin uuid;
begin
  if new.roles is distinct from old.roles or new.role is distinct from old.role or new.status is distinct from old.status then
    select id into primary_admin from public.profiles where role='admin' order by created_at asc limit 1;
    if old.id=primary_admin and (select auth.uid()) is distinct from old.id then
      raise exception 'Le compte administrateur principal et ses permissions sont protégés.';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_primary_admin_roles() from public, anon, authenticated;
drop trigger if exists guard_primary_admin_roles on public.profiles;
create trigger guard_primary_admin_roles before update of roles, role, status on public.profiles
for each row execute function public.guard_primary_admin_roles();

-- Lock the first administrator's email and password in Supabase Auth as well as in the admin UI.
create or replace function public.prevent_primary_admin_auth_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare primary_admin uuid;
begin
  select id into primary_admin from public.profiles where role='admin' order by created_at asc limit 1;
  if old.id=primary_admin and (new.email is distinct from old.email or new.encrypted_password is distinct from old.encrypted_password) then
    raise exception 'Les identifiants du compte administrateur principal sont verrouillés.';
  end if;
  return new;
end;
$$;
revoke all on function public.prevent_primary_admin_auth_change() from public, anon, authenticated;
drop trigger if exists prevent_primary_admin_auth_change on auth.users;
create trigger prevent_primary_admin_auth_change before update of email, encrypted_password on auth.users
for each row execute function public.prevent_primary_admin_auth_change();

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "admins read member sanctions" on public.member_sanctions;
drop policy if exists "members read own sanctions" on public.member_sanctions;
create policy "admins read member sanctions" on public.member_sanctions for select to authenticated using ((select public.is_admin()));
create policy "members read own sanctions" on public.member_sanctions for select to authenticated using (member_id = (select auth.uid()));

create or replace function public.admin_set_member_restriction(target_user uuid, restriction_status text, reason_text text, duration_hours integer default null)
returns void language plpgsql security definer set search_path = '' as $$
declare expiry timestamptz;
begin
  if not public.is_admin() then raise exception 'Action réservée à un administrateur.'; end if;
  if target_user = auth.uid() then raise exception 'Tu ne peux pas modifier ton propre accès.'; end if;
  if restriction_status not in ('suspended','banned') then raise exception 'Sanction invalide.'; end if;
  if length(trim(coalesce(reason_text,''))) < 3 or length(reason_text) > 2000 then raise exception 'Le motif doit contenir entre 3 et 2000 caractères.'; end if;
  if restriction_status = 'suspended' and duration_hours not in (24,168,720) then raise exception 'Durée de suspension invalide.'; end if;
  if restriction_status = 'banned' and duration_hours is not null then raise exception 'Un bannissement définitif ne prend pas de durée.'; end if;
  if not exists(select 1 from public.profiles where id = target_user and role <> 'admin' and status = 'active') then raise exception 'Compte membre introuvable ou protégé.'; end if;
  if restriction_status = 'suspended' then expiry := now() + make_interval(hours => duration_hours); else expiry := null; end if;
  update public.profiles set status = restriction_status, suspended_until = expiry, restriction_reason = trim(reason_text) where id = target_user;
  insert into public.member_sanctions(member_id,admin_id,action,reason,expires_at) values(target_user,auth.uid(),case when restriction_status='suspended' then 'suspend' else 'ban' end,trim(reason_text),expiry);
end;
$$;
revoke all on function public.admin_set_member_restriction(uuid,text,text,integer) from public;
grant execute on function public.admin_set_member_restriction(uuid,text,text,integer) to authenticated;

create or replace function public.admin_edit_member_sanction(target_sanction uuid, reason_text text, new_expires_at timestamptz default null)
returns void language plpgsql security definer set search_path = '' as $$
declare sanction_row record; latest_id uuid; member_status text;
begin
  if not (select public.is_admin()) then raise exception 'Action réservée à un administrateur.'; end if;
  if length(trim(coalesce(reason_text,''))) < 3 or length(reason_text) > 2000 then raise exception 'Le motif doit contenir entre 3 et 2000 caractères.'; end if;
  select id,member_id,action into sanction_row from public.member_sanctions where id=target_sanction;
  if not found then raise exception 'Antécédent introuvable.'; end if;
  if sanction_row.action not in ('suspend','ban') then raise exception 'Cet événement système ne peut pas être modifié.'; end if;
  if sanction_row.action='ban' and new_expires_at is not null then raise exception 'Un bannissement définitif ne prend pas de date de fin.'; end if;
  if sanction_row.action='suspend' and (new_expires_at is null or new_expires_at <= now() or new_expires_at > now()+interval '365 days') then raise exception 'La fin de suspension doit être dans les 365 prochains jours.'; end if;
  update public.member_sanctions set reason=trim(reason_text),expires_at=new_expires_at where id=target_sanction;
  select id into latest_id from public.member_sanctions where member_id=sanction_row.member_id order by created_at desc,id desc limit 1;
  select status into member_status from public.profiles where id=sanction_row.member_id;
  if latest_id=target_sanction and member_status in ('suspended','banned') then
    update public.profiles set restriction_reason=trim(reason_text),suspended_until=case when sanction_row.action='suspend' then new_expires_at else null end where id=sanction_row.member_id;
  end if;
end;
$$;
revoke all on function public.admin_edit_member_sanction(uuid,text,timestamptz) from public;
grant execute on function public.admin_edit_member_sanction(uuid,text,timestamptz) to authenticated;

create or replace function public.admin_delete_member_sanction(target_sanction uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare sanction_action text;
begin
  if not (select public.is_admin()) then raise exception 'Action réservée à un administrateur.'; end if;
  select action into sanction_action from public.member_sanctions where id=target_sanction;
  if not found then raise exception 'Antécédent introuvable.'; end if;
  delete from public.member_sanctions where id=target_sanction;
end;
$$;
revoke all on function public.admin_delete_member_sanction(uuid) from public;
grant execute on function public.admin_delete_member_sanction(uuid) to authenticated;

create or replace function public.restore_expired_own_suspension()
returns boolean language plpgsql security definer set search_path = '' as $$
declare affected integer := 0;
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  update public.profiles set status='active', suspended_until=null, restriction_reason=''
    where id=auth.uid() and status='suspended' and suspended_until <= now();
  get diagnostics affected = row_count;
  if affected > 0 then
    insert into public.member_sanctions(member_id,admin_id,action,reason)
      values(auth.uid(),auth.uid(),'restore','Fin automatique de la suspension temporaire');
  end if;
  return affected > 0;
end;
$$;
revoke all on function public.restore_expired_own_suspension() from public;
grant execute on function public.restore_expired_own_suspension() to authenticated;
-- Remove toute policy résiduelle sur les tables applicatives avant de reconstruire
-- l'ensemble exact ci-dessous : les policies permissives s'additionnent dans PostgreSQL.
do $$
declare old_policy record;
begin
  for old_policy in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles','reports','projects','team_roles','report_disputes','member_warnings','member_sanctions','warning_disputes','sanction_disputes','tasks','task_comments','team_absences','late_notices','team_messages','team_direct_messages','team_announcements')
  loop
    execute format('drop policy %I on public.%I', old_policy.policyname, old_policy.tablename);
  end loop;
end;
$$;

drop policy if exists "admins read member sanctions" on public.member_sanctions;
create policy "admins read member sanctions" on public.member_sanctions
for select to authenticated using ((select public.is_admin()));
drop policy if exists "members read own sanctions" on public.member_sanctions;
create policy "members read own sanctions" on public.member_sanctions
for select to authenticated using (member_id = (select auth.uid()));

revoke all on table public.profiles, public.reports, public.projects, public.team_roles,
  public.report_disputes, public.member_warnings, public.warning_disputes, public.sanction_disputes,
  public.tasks, public.task_comments, public.team_absences, public.late_notices,
  public.team_messages, public.team_direct_messages, public.team_announcements
  from anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.reports to authenticated;
grant select, insert, update, delete on public.projects to authenticated;
grant select, insert, update, delete on public.team_roles to authenticated;
grant select, insert on public.report_disputes to authenticated;
grant select, insert, update, delete on public.member_warnings to authenticated;
grant select, insert, update, delete on public.warning_disputes to authenticated;
grant select, insert, update on public.sanction_disputes to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert, delete on public.task_comments to authenticated;
grant select, insert, update, delete on public.team_absences to authenticated;
grant select, insert, update, delete on public.late_notices to authenticated;
grant select, insert, delete on public.team_messages to authenticated;
grant select, insert, delete on public.team_direct_messages to authenticated;
grant select, insert, update, delete on public.team_announcements to authenticated;

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
  select exists (select 1 from public.profiles where id = (select auth.uid()) and (status = 'active' or (status = 'suspended' and suspended_until <= now())));
$$;
revoke all on function public.is_active_member() from public;
grant execute on function public.is_active_member() to authenticated;
drop policy if exists "active members read absences" on public.team_absences;
create policy "active members read absences" on public.team_absences for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "members submit own absences" on public.team_absences;
create policy "members submit own absences" on public.team_absences for insert to authenticated
with check ((select public.is_active_member()) and user_id = (select auth.uid()) and status = 'pending' and absence_kind = 'planned' and recorded_by is null);
drop policy if exists "admins record absences" on public.team_absences;
create policy "admins record absences" on public.team_absences for insert to authenticated
with check ((select public.is_admin()) and status = 'recorded' and absence_kind = 'unjustified' and recorded_by = (select auth.uid()));
drop policy if exists "admins review absences" on public.team_absences;
create policy "admins review absences" on public.team_absences for update to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "admins delete absences" on public.team_absences;
create policy "admins delete absences" on public.team_absences for delete to authenticated using ((select public.is_admin()));

drop policy if exists "active members read late notices" on public.late_notices;
create policy "active members read late notices" on public.late_notices for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "members submit own late notices" on public.late_notices;
create policy "members submit own late notices" on public.late_notices for insert to authenticated
with check ((select public.is_active_member()) and user_id = (select auth.uid()) and status = 'pending' and late_kind = 'reported' and recorded_by is null);
drop policy if exists "admins record late notices" on public.late_notices;
create policy "admins record late notices" on public.late_notices for insert to authenticated
with check ((select public.is_admin()) and status = 'recorded' and late_kind in ('justified','unjustified') and recorded_by = (select auth.uid()));
drop policy if exists "admins review late notices" on public.late_notices;
create policy "admins review late notices" on public.late_notices for update to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "admins delete late notices" on public.late_notices;
create policy "admins delete late notices" on public.late_notices for delete to authenticated using ((select public.is_admin()));

drop policy if exists "members read targeted announcements" on public.team_announcements;
create policy "members read targeted announcements" on public.team_announcements for select to authenticated
using ((select public.is_active_member()) and active and starts_at <= now() and (ends_at is null or ends_at > now()) and (recipient_id is null or recipient_id = (select auth.uid())));
drop policy if exists "admins manage announcements" on public.team_announcements;
create policy "admins manage announcements" on public.team_announcements for all to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "active members read team messages" on public.team_messages;
create policy "active members read team messages" on public.team_messages for select to authenticated
using ((select public.is_active_member()));
drop policy if exists "active members send own team messages" on public.team_messages;
create policy "active members send own team messages" on public.team_messages for insert to authenticated
with check ((select public.is_active_member()) and user_id = (select auth.uid()));
drop policy if exists "participants read direct messages" on public.team_direct_messages;
create policy "participants read direct messages" on public.team_direct_messages for select to authenticated
using ((select public.is_active_member()) and ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id));
drop policy if exists "active members send direct messages" on public.team_direct_messages;
create policy "active members send direct messages" on public.team_direct_messages for insert to authenticated
with check ((select public.is_active_member()) and sender_id = (select auth.uid()) and recipient_id <> (select auth.uid()) and exists (
  select 1 from public.profiles recipient where recipient.id = recipient_id and recipient.status = 'active'
));
drop policy if exists "authors or admins delete direct messages" on public.team_direct_messages;
create policy "authors or admins delete direct messages" on public.team_direct_messages for delete to authenticated
using ((select public.is_admin()) or ((select public.is_active_member()) and sender_id = (select auth.uid())));
drop policy if exists "authors or admins delete team messages" on public.team_messages;
create policy "authors or admins delete team messages" on public.team_messages for delete to authenticated
using ((select public.is_admin()) or ((select public.is_active_member()) and user_id = (select auth.uid())));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_messages') then
    execute 'alter publication supabase_realtime add table public.team_messages';
  end if;
end;
$$;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'team_direct_messages') then
    execute 'alter publication supabase_realtime add table public.team_direct_messages';
  end if;
end;
$$;

drop policy if exists "active members read team roles" on public.team_roles;
create policy "active members read team roles" on public.team_roles for select to authenticated using ((select public.is_active_member()));
drop policy if exists "admins manage team roles" on public.team_roles;
create policy "admins manage team roles" on public.team_roles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create or replace function public.guard_task_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by <> (select auth.uid()) and not (select public.is_admin()) then
      raise exception 'Une tâche doit être créée par le compte connecté';
    end if;
  elsif new.created_by is distinct from old.created_by and not (select public.is_admin()) then
    raise exception 'Le créateur d’une tâche ne peut pas être modifié';
  end if;
  if new.assigned_to is not null and not exists (
    select 1 from public.profiles p where p.id = new.assigned_to and p.status = 'active'
  ) then
    raise exception 'La tâche doit être attribuée à un membre actif';
  end if;
  if exists (
    select 1 from unnest(coalesce(new.assignee_ids, '{}'::uuid[])) selected(member_id)
    where not exists (select 1 from public.profiles p where p.id = selected.member_id and p.status = 'active')
  ) then
    raise exception 'Tous les responsables doivent être des membres actifs';
  end if;
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.guard_task_write() from public;
drop trigger if exists guard_task_write on public.tasks;
create trigger guard_task_write before insert or update on public.tasks
for each row execute function public.guard_task_write();
drop policy if exists "active members read tasks" on public.tasks;
create policy "active members read tasks" on public.tasks for select to authenticated
using ((select public.is_active_member()));
drop policy if exists "active members create tasks" on public.tasks;
create policy "active members create tasks" on public.tasks for insert to authenticated
with check ((select public.is_active_member()) and created_by = (select auth.uid()));
drop policy if exists "active members update tasks" on public.tasks;
create policy "active members update tasks" on public.tasks for update to authenticated
using ((select public.is_active_member()))
with check ((select public.is_active_member()));
drop policy if exists "admins or creators delete tasks" on public.tasks;
create policy "admins or creators delete tasks" on public.tasks for delete to authenticated
using ((select public.is_admin()) or created_by = (select auth.uid()));
drop policy if exists "active members read task comments" on public.task_comments;
create policy "active members read task comments" on public.task_comments for select to authenticated
using ((select public.is_active_member()));
drop policy if exists "active members add own task comments" on public.task_comments;
create policy "active members add own task comments" on public.task_comments for insert to authenticated
with check ((select public.is_active_member()) and user_id = (select auth.uid()) and exists (
  select 1 from public.tasks t where t.id = task_id
));
drop policy if exists "authors or admins delete task comments" on public.task_comments;
create policy "authors or admins delete task comments" on public.task_comments for delete to authenticated
using ((select public.is_admin()) or user_id = (select auth.uid()));
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
drop policy if exists "members read own sanction disputes" on public.sanction_disputes;
create policy "members read own sanction disputes" on public.sanction_disputes for select to authenticated
using (member_id=(select auth.uid()) or (select public.is_admin()));
drop policy if exists "members contest own sanctions" on public.sanction_disputes;
create policy "members contest own sanctions" on public.sanction_disputes for insert to authenticated
with check (member_id=(select auth.uid()) and exists (
  select 1 from public.member_sanctions s join public.profiles p on p.id=s.member_id
  where s.id=sanction_id and s.member_id=(select auth.uid()) and s.action in ('suspend','ban') and p.status in ('suspended','banned')
) and status='open' and admin_note='' and reviewed_by is null and reviewed_at is null);
drop policy if exists "admin review sanction disputes" on public.sanction_disputes;
create policy "admin review sanction disputes" on public.sanction_disputes for update to authenticated
using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists "insert own report disputes" on public.report_disputes;
create policy "insert own report disputes" on public.report_disputes for insert to authenticated
with check (user_id=(select auth.uid()) and (select public.is_active_member()) and exists (
  select 1 from public.reports r where r.id = report_id and r.user_id = (select auth.uid())
));

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
update public.profiles p
set nickname = coalesce(nullif(u.raw_user_meta_data ->> 'nickname', ''), '')
from auth.users u where p.id = u.id and p.nickname = '';

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
for select to authenticated using ((select public.is_admin()) or ((select public.is_active_member()) and status = 'active'));
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

-- Webhooks Discord privés. Accès API interdit aux rôles du navigateur ; seule l'Edge Function utilise service_role.
create table if not exists public.team_webhooks (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  username_mode text not null default 'named' check (username_mode in ('named', 'brand')),
  avatar_url text check (avatar_url is null or (length(avatar_url) <= 2048 and avatar_url ~ '^https://')),
  mention_target text not null default '' check (mention_target = '' or mention_target in ('@everyone', '@here') or mention_target ~ '^<@!?[0-9]{15,22}>$' or mention_target ~ '^<@&[0-9]{15,22}>$'),
  embed_image_url text check (embed_image_url is null or (length(embed_image_url) <= 2048 and embed_image_url ~ '^https://')),
  extra_embeds jsonb not null default '[]'::jsonb check (jsonb_typeof(extra_embeds) = 'array' and jsonb_array_length(extra_embeds) <= 2),
  message_template text not null default '' check (length(message_template) <= 1800),
  webhook_url text not null check (length(webhook_url) <= 2048),
  events text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.team_webhooks enable row level security;
revoke all on table public.team_webhooks from public, anon, authenticated;
grant all on table public.team_webhooks to service_role;
comment on table public.team_webhooks is 'Secret Discord webhook URLs; access only from trusted server functions.';
create table if not exists public.team_webhook_deliveries (
  webhook_id uuid not null references public.team_webhooks(id) on delete cascade,
  event_type text not null,
  record_id uuid not null,
  sent_at timestamptz not null default now(),
  primary key (webhook_id, event_type, record_id)
);
alter table public.team_webhook_deliveries enable row level security;
revoke all on table public.team_webhook_deliveries from public, anon, authenticated;
grant all on table public.team_webhook_deliveries to service_role;

-- Notifications and administrator-only chat deletion (idempotent migration).
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
alter table public.profiles
  add column if not exists theme_preference text not null default 'light',
  add column if not exists accent_color text not null default '#2f7655';

alter table public.profiles drop constraint if exists profiles_theme_preference_check;
alter table public.profiles add constraint profiles_theme_preference_check
  check (theme_preference in ('light','dark'));
alter table public.profiles drop constraint if exists profiles_accent_color_check;
alter table public.profiles add constraint profiles_accent_color_check
  check (accent_color in ('#2f7655','#315f9b','#684a9b','#a4475d','#167c80'));

create or replace function public.save_my_appearance(theme_value text, accent_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  if theme_value not in ('light','dark') then raise exception 'Thème invalide.'; end if;
  if accent_value not in ('#2f7655','#315f9b','#684a9b','#a4475d','#167c80') then raise exception 'Couleur invalide.'; end if;
  update public.profiles
    set theme_preference = theme_value, accent_color = accent_value
    where id = auth.uid() and status = 'active';
  if not found then raise exception 'Compte actif introuvable.'; end if;
end;
$$;
revoke all on function public.save_my_appearance(text,text) from public, anon;
grant execute on function public.save_my_appearance(text,text) to authenticated;

-- Identifiant de connexion unique pour chaque membre (également ajouté comme migration datée).
-- Every member gets a unique login identifier, including existing email accounts.
alter table public.profiles add column if not exists login_identifier text;

with candidates as (
  select p.id,
    coalesce(
      nullif(lower(u.raw_app_meta_data->>'login_identifier'), ''),
      left(coalesce(nullif(trim(regexp_replace(lower(coalesce(nullif(p.nickname,''),nullif(p.display_name,''),split_part(u.email,'@',1),'membre')), '[^a-z0-9]+','_','g')),''),'membre'),21)
        ||'_'||left(replace(p.id::text,'-',''),6)
    ) as identifier
  from public.profiles p join auth.users u on u.id=p.id
  where p.login_identifier is null
)
update public.profiles p set login_identifier=c.identifier from candidates c where p.id=c.id;

-- Repair possible duplicate legacy aliases deterministically before adding uniqueness.
with duplicates as (
  select id, login_identifier, row_number() over (partition by lower(login_identifier) order by id) as n
  from public.profiles
)
update public.profiles p set login_identifier=left(d.login_identifier,21)||'_'||left(replace(p.id::text,'-',''),6)
from duplicates d where d.id=p.id and d.n>1;

alter table public.profiles alter column login_identifier set not null;
alter table public.profiles drop constraint if exists profiles_login_identifier_check;
alter table public.profiles add constraint profiles_login_identifier_check
  check (login_identifier ~ '^[a-z0-9][a-z0-9._-]{2,29}$');
create unique index if not exists profiles_login_identifier_unique_idx on public.profiles(lower(login_identifier));

create table if not exists public.identifier_login_attempts (
  identifier_hash text primary key check (identifier_hash ~ '^[a-f0-9]{64}$'),
  attempts integer not null default 0 check (attempts >= 0),
  window_started_at timestamptz not null default now()
);
alter table public.identifier_login_attempts enable row level security;
revoke all on public.identifier_login_attempts from public, anon, authenticated;

create or replace function public.consume_identifier_login_attempt(identifier_digest text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare attempt_count integer;
begin
  if identifier_digest !~ '^[a-f0-9]{64}$' then return false; end if;
  insert into public.identifier_login_attempts(identifier_hash, attempts, window_started_at)
  values(identifier_digest,1,now())
  on conflict(identifier_hash) do update
    set attempts = case when public.identifier_login_attempts.window_started_at < now()-interval '15 minutes' then 1 else public.identifier_login_attempts.attempts+1 end,
        window_started_at = case when public.identifier_login_attempts.window_started_at < now()-interval '15 minutes' then now() else public.identifier_login_attempts.window_started_at end
  returning attempts into attempt_count;
  return attempt_count <= 8;
end;
$$;
revoke all on function public.consume_identifier_login_attempt(text) from public, anon, authenticated;
grant execute on function public.consume_identifier_login_attempt(text) to service_role;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare generated_identifier text;
begin
  generated_identifier := lower(coalesce(nullif(new.raw_app_meta_data->>'login_identifier',''),
    left(coalesce(nullif(trim(regexp_replace(lower(coalesce(nullif(new.raw_user_meta_data->>'nickname',''),nullif(new.raw_user_meta_data->>'display_name',''),split_part(new.email,'@',1),'membre')), '[^a-z0-9]+','_','g')),''),'membre'),21)
    ||'_'||left(replace(new.id::text,'-',''),6)));
  insert into public.profiles (id, display_name, role, status, login_identifier)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'Membre'), 'developer', 'pending', generated_identifier);
  return new;
end;
$$;

create or replace function public.clear_identifier_login_attempt(identifier_digest text)
returns void language sql security definer set search_path = '' as $$
  delete from public.identifier_login_attempts where identifier_hash = identifier_digest and identifier_digest ~ '^[a-f0-9]{64}$';
$$;
revoke all on function public.clear_identifier_login_attempt(text) from public, anon, authenticated;
grant execute on function public.clear_identifier_login_attempt(text) to service_role;

-- Autorise les couleurs hex personnalisées choisies dans les préférences du compte.
alter table public.profiles drop constraint if exists profiles_accent_color_check;
alter table public.profiles add constraint profiles_accent_color_check
  check (accent_color ~ '^#[0-9a-fA-F]{6}$');

create or replace function public.save_my_appearance(theme_value text, accent_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  if theme_value not in ('light','dark') then raise exception 'Thème invalide.'; end if;
  if accent_value !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Couleur invalide.'; end if;
  update public.profiles set theme_preference = theme_value, accent_color = lower(accent_value)
    where id = auth.uid() and status = 'active';
  if not found then raise exception 'Compte actif introuvable.'; end if;
end;
$$;
revoke all on function public.save_my_appearance(text,text) from public, anon;
grant execute on function public.save_my_appearance(text,text) to authenticated;
