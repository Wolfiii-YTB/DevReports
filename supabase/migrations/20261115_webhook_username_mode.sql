-- Store the Discord bot display-name preference per destination.
alter table public.team_webhooks
  add column if not exists username_mode text not null default 'named'
  check (username_mode in ('named', 'brand'));

comment on column public.team_webhooks.username_mode is
  'Discord sender name style: named = configured name plus DevReports; brand = DevReports only.';
