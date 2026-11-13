-- Optional ping, template, primary embed image, and up to two extra embeds.
alter table public.team_webhooks
  add column if not exists mention_target text not null default ''
    check (mention_target = '' or mention_target in ('@everyone', '@here') or mention_target ~ '^<@!?[0-9]{15,22}>$' or mention_target ~ '^<@&[0-9]{15,22}>$'),
  add column if not exists embed_image_url text
    check (embed_image_url is null or (length(embed_image_url) <= 2048 and embed_image_url ~ '^https://')),
  add column if not exists extra_embeds jsonb not null default '[]'::jsonb
    check (jsonb_typeof(extra_embeds) = 'array' and jsonb_array_length(extra_embeds) <= 2),
  add column if not exists message_template text not null default ''
    check (length(message_template) <= 1800);

comment on column public.team_webhooks.mention_target is 'Explicitly allowed Discord mention for this webhook, or empty.';
comment on column public.team_webhooks.embed_image_url is 'Optional HTTPS image for the primary event embed.';
comment on column public.team_webhooks.extra_embeds is 'Up to two optional extra embeds, validated by the Edge Function.';
comment on column public.team_webhooks.message_template is 'Optional event message template with supported placeholders.';
