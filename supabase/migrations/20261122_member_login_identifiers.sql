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

create or replace function public.clear_identifier_login_attempt(identifier_digest text)
returns void language sql security definer set search_path = '' as $$
  delete from public.identifier_login_attempts where identifier_hash = identifier_digest and identifier_digest ~ '^[a-f0-9]{64}$';
$$;
revoke all on function public.clear_identifier_login_attempt(text) from public, anon, authenticated;
grant execute on function public.clear_identifier_login_attempt(text) to service_role;

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
