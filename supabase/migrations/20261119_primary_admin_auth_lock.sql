-- Keep the original (oldest) administrator's email and password immutable.
create or replace function public.prevent_primary_admin_auth_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare primary_admin uuid;
begin
  select id into primary_admin
  from public.profiles
  where role = 'admin'
  order by created_at asc
  limit 1;

  if old.id = primary_admin
    and (new.email is distinct from old.email or new.encrypted_password is distinct from old.encrypted_password) then
    raise exception 'Les identifiants du compte administrateur principal sont verrouillés.';
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_primary_admin_auth_change() from public, anon, authenticated;
drop trigger if exists prevent_primary_admin_auth_change on auth.users;
create trigger prevent_primary_admin_auth_change
before update of email, encrypted_password on auth.users
for each row execute function public.prevent_primary_admin_auth_change();
