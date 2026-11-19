-- Distinguish initial review from final DevDocs approval.
begin;
alter table public.map_docs drop constraint if exists map_docs_status_check;
alter table public.map_docs add constraint map_docs_status_check
  check (status in ('idea','approved','building','review','checking','rework','integrated','rejected'));

create or replace function public.review_map_doc(map_doc_id uuid, decision text, note_value text default '')
returns void language plpgsql security definer set search_path = '' as $$
declare doc_row public.map_docs%rowtype;
begin
  if auth.uid() is null or not (select public.is_admin()) then raise exception 'Action réservée à un administrateur.'; end if;
  if decision not in ('checking','approved','rework') then raise exception 'Décision invalide.'; end if;
  if length(trim(coalesce(note_value,''))) > 2000 then raise exception 'Le commentaire est trop long.'; end if;
  select * into doc_row from public.map_docs where id=map_doc_id for update;
  if not found then raise exception 'Fiche DevDocs introuvable.'; end if;
  if decision='checking' then
    if doc_row.status <> 'review' then raise exception 'Seule une fiche en attente peut être marquée comme vérifiée.'; end if;
    update public.map_docs set status='checking',reviewed_by=auth.uid(),reviewed_at=now(),
      review_note=trim(coalesce(note_value,'')),updated_at=now() where id=map_doc_id;
    return;
  end if;
  if doc_row.status not in ('review','checking') then raise exception 'Cette fiche n’attend pas de décision finale.'; end if;
  if decision='rework' and length(trim(coalesce(note_value,''))) < 2 then raise exception 'Explique pourquoi le travail n’est pas terminé.'; end if;
  update public.map_docs set status=case when decision='approved' then 'integrated' else 'rework' end,
    reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(coalesce(note_value,'')),updated_at=now()
    where id=map_doc_id;
end;
$$;
revoke all on function public.review_map_doc(uuid,text,text) from public, anon;
grant execute on function public.review_map_doc(uuid,text,text) to authenticated;
commit;
