-- Optional per-webhook Discord sender avatar (URL only; webhook URLs remain secret).
alter table public.team_webhooks
  add column if not exists avatar_url text
  check (avatar_url is null or (length(avatar_url) <= 2048 and avatar_url ~ '^https://'));

comment on column public.team_webhooks.avatar_url is
  'Optional HTTPS image URL used as the Discord webhook sender avatar.';
