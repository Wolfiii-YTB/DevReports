-- Multiple named Discord webhooks with independent event subscriptions.
create table if not exists public.team_webhooks (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  webhook_url text not null check (length(webhook_url) <= 2048),
  events text[] not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.team_webhooks enable row level security;
revoke all on table public.team_webhooks from public, anon, authenticated;
grant all on table public.team_webhooks to service_role;

-- Preserve the existing single webhook when upgrading the previous version.
do $$
begin
  if to_regclass('public.team_webhook_config') is not null then
    execute $copy$
      insert into public.team_webhooks(name, webhook_url, events, created_by, created_at, updated_at)
      select 'Webhook principal', legacy.webhook_url, legacy.events, legacy.updated_by,
             coalesce(legacy.updated_at, now()), coalesce(legacy.updated_at, now())
      from public.team_webhook_config legacy
      where not exists (
        select 1 from public.team_webhooks current_webhook
        where current_webhook.webhook_url = legacy.webhook_url
      )
    $copy$;
  end if;
end;
$$;

drop table if exists public.team_webhook_config;

-- Idempotency is scoped to a webhook so every selected destination gets its own event once.
drop table if exists public.team_webhook_deliveries;
create table public.team_webhook_deliveries (
  webhook_id uuid not null references public.team_webhooks(id) on delete cascade,
  event_type text not null,
  record_id uuid not null,
  sent_at timestamptz not null default now(),
  primary key (webhook_id, event_type, record_id)
);
alter table public.team_webhook_deliveries enable row level security;
revoke all on table public.team_webhook_deliveries from public, anon, authenticated;
grant all on table public.team_webhook_deliveries to service_role;
