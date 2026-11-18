-- Assignment and completion review workflow for map DevDocs.
begin;
alter table public.map_docs
  add column if not exists assignee_ids uuid[] not null default '{}'::uuid[],
  add column if not exists submitted_by uuid references public.profiles(id) on delete set null,
  add column if not exists submitted_at timestamptz,
  add column if not exists submission_note text not null default '',
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text not null default '';
alter table public.map_docs drop constraint if exists map_docs_status_check;
alter table public.map_docs add constraint map_docs_status_check
  check (status in ('idea','approved','building','review','rework','integrated','rejected'));
create index if not exists map_docs_assignees_idx on public.map_docs using gin(assignee_ids);

create or replace function public.start_map_doc(map_doc_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare doc_row public.map_docs%rowtype;
begin
  if auth.uid() is null or not (select public.is_active_member()) then raise exception 'Connexion active requise.'; end if;
  select * into doc_row from public.map_docs where id = map_doc_id for update;
  if not found then raise exception 'Fiche DevDocs introuvable.'; end if;
  if not ((select auth.uid()) = any(coalesce(doc_row.assignee_ids, '{}'::uuid[]))) then raise exception 'Cette fiche ne t’est pas attribuée.'; end if;
  if doc_row.status not in ('approved','rework') then raise exception 'Cette fiche ne peut pas être démarrée.'; end if;
  update public.map_docs set status='building',updated_at=now() where id=map_doc_id;
end;
$$;
revoke all on function public.start_map_doc(uuid) from public, anon;
grant execute on function public.start_map_doc(uuid) to authenticated;

create or replace function public.submit_map_doc_for_review(map_doc_id uuid, note_value text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare doc_row public.map_docs%rowtype;
begin
  if auth.uid() is null or not (select public.is_active_member()) then raise exception 'Connexion active requise.'; end if;
  select * into doc_row from public.map_docs where id=map_doc_id for update;
  if not found then raise exception 'Fiche DevDocs introuvable.'; end if;
  if not ((select auth.uid()) = any(coalesce(doc_row.assignee_ids, '{}'::uuid[]))) then raise exception 'Cette fiche ne t’est pas attribuée.'; end if;
  if doc_row.status not in ('building','rework') then raise exception 'Cette fiche ne peut pas encore être envoyée en vérification.'; end if;
  if length(trim(coalesce(note_value,''))) > 2000 then raise exception 'Le commentaire est trop long.'; end if;
  update public.map_docs set status='review',submitted_by=auth.uid(),submitted_at=now(),
    submission_note=trim(coalesce(note_value,'')),reviewed_by=null,reviewed_at=null,review_note='',updated_at=now()
    where id=map_doc_id;
end;
$$;
revoke all on function public.submit_map_doc_for_review(uuid,text) from public, anon;
grant execute on function public.submit_map_doc_for_review(uuid,text) to authenticated;

create or replace function public.review_map_doc(map_doc_id uuid, decision text, note_value text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare doc_row public.map_docs%rowtype;
begin
  if auth.uid() is null or not (select public.is_admin()) then raise exception 'Action réservée à un administrateur.'; end if;
  if decision not in ('approved','rework') then raise exception 'Décision invalide.'; end if;
  if length(trim(coalesce(note_value,''))) > 2000 then raise exception 'Le commentaire est trop long.'; end if;
  select * into doc_row from public.map_docs where id=map_doc_id for update;
  if not found then raise exception 'Fiche DevDocs introuvable.'; end if;
  if doc_row.status <> 'review' then raise exception 'Cette fiche n’attend pas de vérification.'; end if;
  if decision='rework' and length(trim(coalesce(note_value,''))) < 2 then raise exception 'Ajoute un commentaire expliquant ce qui est à reprendre.'; end if;
  update public.map_docs set status=case when decision='approved' then 'integrated' else 'rework' end,
    reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(coalesce(note_value,'')),updated_at=now()
    where id=map_doc_id;
end;
$$;
revoke all on function public.review_map_doc(uuid,text,text) from public, anon;
grant execute on function public.review_map_doc(uuid,text,text) to authenticated;
commit;
