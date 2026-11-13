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
