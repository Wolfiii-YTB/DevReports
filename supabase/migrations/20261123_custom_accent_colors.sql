alter table public.profiles drop constraint if exists profiles_accent_color_check;
alter table public.profiles add constraint profiles_accent_color_check
  check (accent_color ~ '^#[0-9a-fA-F]{6}$');

create or replace function public.save_my_appearance(theme_value text, accent_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  if theme_value not in ('light','dark') then raise exception 'Thème invalide.'; end if;
  if accent_value !~ '^#[0-9a-fA-F]{6}$' then raise exception 'Couleur invalide.'; end if;
  update public.profiles
    set theme_preference = theme_value, accent_color = lower(accent_value)
    where id = auth.uid() and status = 'active';
  if not found then raise exception 'Compte actif introuvable.'; end if;
end;
$$;
revoke all on function public.save_my_appearance(text,text) from public, anon;
grant execute on function public.save_my_appearance(text,text) to authenticated;
