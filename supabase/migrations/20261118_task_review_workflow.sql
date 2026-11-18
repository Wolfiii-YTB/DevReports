-- Developer task delivery and administrator review workflow.
begin;
alter table public.tasks
  add column if not exists submitted_by uuid references public.profiles(id) on delete set null,
  add column if not exists submitted_at timestamptz,
  add column if not exists submission_note text not null default '',
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text not null default '';

alter table public.tasks drop constraint if exists tasks_status_check;
alter table public.tasks drop constraint if exists task_status_check;
alter table public.tasks add constraint task_status_check
  check (status in ('backlog','todo','doing','review','rework','done'));

drop policy if exists "active members create tasks" on public.tasks;
drop policy if exists "active members update tasks" on public.tasks;
drop policy if exists "admins or creators delete tasks" on public.tasks;
drop policy if exists "admins create tasks" on public.tasks;
drop policy if exists "admins manage tasks" on public.tasks;
drop policy if exists "assigned members submit tasks" on public.tasks;
drop policy if exists "admins delete tasks" on public.tasks;

create policy "admins create tasks" on public.tasks for insert to authenticated
  with check ((select public.is_admin()) and created_by = (select auth.uid()));
create policy "admins manage tasks" on public.tasks for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "assigned members submit tasks" on public.tasks for update to authenticated
  using ((select public.is_active_member()) and (select auth.uid()) = any(coalesce(assignee_ids, '{}'::uuid[])) and status in ('backlog','todo','doing','rework'))
  with check ((select public.is_active_member()) and (select auth.uid()) = any(coalesce(assignee_ids, '{}'::uuid[])) and ((status = 'review' and submitted_by = (select auth.uid())) or status = 'doing'));
create policy "admins delete tasks" on public.tasks for delete to authenticated
  using ((select public.is_admin()));

create or replace function public.guard_task_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if not (select public.is_admin()) or new.created_by <> (select auth.uid()) then
      raise exception 'Seuls les administrateurs peuvent créer une tâche.';
    end if;
  elsif (select public.is_admin()) then
    null;
  else
    if not (select public.is_active_member())
       or not ((select auth.uid()) = any(coalesce(old.assignee_ids, '{}'::uuid[])))
       or not (
         (new.status='doing' and old.status in ('backlog','todo')
           and (to_jsonb(new)-array['status','updated_at']) is not distinct from (to_jsonb(old)-array['status','updated_at']))
         or
         (new.status='review' and old.status in ('todo','doing','rework')
           and new.submitted_by=(select auth.uid()) and new.submitted_at is not null
           and new.reviewed_by is not distinct from old.reviewed_by
           and new.reviewed_at is not distinct from old.reviewed_at
           and new.review_note is not distinct from old.review_note
           and (to_jsonb(new)-array['status','submitted_by','submitted_at','submission_note','updated_at'])
             is not distinct from (to_jsonb(old)-array['status','submitted_by','submitted_at','submission_note','updated_at']))
       ) then
      raise exception 'Tu peux uniquement envoyer une tâche qui t’est attribuée pour vérification.';
    end if;
  end if;
  if new.assigned_to is not null and not exists (
    select 1 from public.profiles p where p.id = new.assigned_to and p.status = 'active'
  ) then raise exception 'La tâche doit être attribuée à un membre actif'; end if;
  if exists (
    select 1 from unnest(coalesce(new.assignee_ids, '{}'::uuid[])) selected(member_id)
    where not exists (select 1 from public.profiles p where p.id = selected.member_id and p.status = 'active')
  ) then raise exception 'Tous les responsables doivent être des membres actifs'; end if;
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.guard_task_write() from public, anon, authenticated;

create or replace function public.submit_task_for_review(task_id uuid, note_value text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare task_row public.tasks%rowtype;
begin
  if auth.uid() is null or not (select public.is_active_member()) then raise exception 'Connexion active requise.'; end if;
  select * into task_row from public.tasks where id = task_id for update;
  if not found then raise exception 'Tâche introuvable.'; end if;
  if not ((select auth.uid()) = any(coalesce(task_row.assignee_ids, '{}'::uuid[]))) then raise exception 'Cette tâche ne t’est pas attribuée.'; end if;
  if task_row.status not in ('todo','doing','rework') then raise exception 'Cette tâche ne peut pas encore être envoyée en vérification.'; end if;
  if length(trim(coalesce(note_value,''))) > 2000 then raise exception 'Le commentaire est trop long.'; end if;
  update public.tasks set status='review', submitted_by=auth.uid(), submitted_at=now(),
    submission_note=trim(coalesce(note_value,'')), reviewed_by=null, reviewed_at=null, review_note=''
    where id=task_id;
end;
$$;
revoke all on function public.submit_task_for_review(uuid,text) from public, anon;
grant execute on function public.submit_task_for_review(uuid,text) to authenticated;

create or replace function public.start_task(task_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare task_row public.tasks%rowtype;
begin
  if auth.uid() is null or not (select public.is_active_member()) then raise exception 'Connexion active requise.'; end if;
  select * into task_row from public.tasks where id=task_id for update;
  if not found then raise exception 'Tâche introuvable.'; end if;
  if not ((select auth.uid()) = any(coalesce(task_row.assignee_ids, '{}'::uuid[]))) then raise exception 'Cette tâche ne t’est pas attribuée.'; end if;
  if task_row.status not in ('backlog','todo') then raise exception 'Cette tâche ne peut pas être démarrée.'; end if;
  update public.tasks set status='doing' where id=task_id;
end;
$$;
revoke all on function public.start_task(uuid) from public, anon;
grant execute on function public.start_task(uuid) to authenticated;

create or replace function public.review_task(task_id uuid, decision text, note_value text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare task_row public.tasks%rowtype;
begin
  if auth.uid() is null or not (select public.is_admin()) then raise exception 'Action réservée à un administrateur.'; end if;
  if decision not in ('approved','rework') then raise exception 'Décision invalide.'; end if;
  if length(trim(coalesce(note_value,''))) > 2000 then raise exception 'Le commentaire est trop long.'; end if;
  select * into task_row from public.tasks where id=task_id for update;
  if not found then raise exception 'Tâche introuvable.'; end if;
  if task_row.status <> 'review' then raise exception 'Cette tâche n’attend pas de vérification.'; end if;
  if decision='rework' and length(trim(coalesce(note_value,''))) < 2 then raise exception 'Ajoute un commentaire expliquant ce qui est à refaire.'; end if;
  update public.tasks set status=case when decision='approved' then 'done' else 'rework' end,
    reviewed_by=auth.uid(), reviewed_at=now(), review_note=trim(coalesce(note_value,''))
    where id=task_id;
end;
$$;
revoke all on function public.review_task(uuid,text,text) from public, anon;
grant execute on function public.review_task(uuid,text,text) to authenticated;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_active_member() to authenticated;
commit;
