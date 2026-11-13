-- Webhook Discord privé, accessible uniquement par Edge Function avec service role.
create table if not exists public.team_webhook_config (
  id boolean primary key default true check (id = true),
  webhook_url text not null,
  events text[] not null default '{}',
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.team_webhook_config enable row level security;
revoke all on table public.team_webhook_config from public, anon, authenticated;
grant all on table public.team_webhook_config to service_role;

comment on table public.team_webhook_config is 'Secret Discord webhook configuration; access only from trusted server functions.';

create table if not exists public.team_webhook_deliveries (
  event_type text not null,
  record_id uuid not null,
  sent_at timestamptz not null default now(),
  primary key (event_type, record_id)
);
alter table public.team_webhook_deliveries enable row level security;
revoke all on table public.team_webhook_deliveries from public, anon, authenticated;
grant all on table public.team_webhook_deliveries to service_role;
