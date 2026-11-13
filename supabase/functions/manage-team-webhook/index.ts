import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
function secret(name: string, groupedName: string) {
  const value = Deno.env.get(name);
  if (value) return value;
  try {
    const grouped = JSON.parse(Deno.env.get(groupedName) || "{}");
    return grouped.default || Object.values(grouped)[0] || "";
  } catch { return ""; }
}
const serviceKey = secret("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS");
const anonKey = secret("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS");
const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") || "").split(",").map((item) => item.trim()).filter(Boolean);
const eventTypes = ["report_created", "absence_requested", "late_reported", "absence_recorded", "late_recorded", "warning_created", "announcement_published"];
class PublicWebhookError extends Error {}

function reply(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), { status, headers: {
    "content-type": "application/json; charset=utf-8", "access-control-allow-origin": origin,
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
    "access-control-allow-methods": "POST, OPTIONS", "vary": "Origin",
  } });
}
function validWebhook(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && (url.hostname === "discord.com" || url.hostname === "discordapp.com") && /^\/api\/webhooks\/\d+\/[A-Za-z0-9._-]+\/?$/.test(url.pathname) && !url.search && !url.hash;
  } catch { return false; }
}
function validAvatar(value: string) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !!url.hostname && !url.username && !url.password;
  } catch { return false; }
}
function clip(value: unknown, max = 900) {
  const text = String(value ?? "").trim();
  return (text || "—").slice(0, max);
}
function eventTitle(type: string) {
  return ({ report_created: "Nouveau rapport", absence_requested: "Demande d’absence", late_reported: "Retard signalé", absence_recorded: "Absence consignée", late_recorded: "Retard consigné", warning_created: "Avertissement attribué", announcement_published: "Nouvelle annonce" } as Record<string, string>)[type] || "Événement d’équipe";
}
async function sendWebhook(url: string, username: string, avatarUrl: string | null, title: string, fields: Array<{ name: string; value: string; inline?: boolean }>) {
  let response: Response;
  try {
    response = await fetch(url, { method: "POST", redirect: "error", signal: AbortSignal.timeout(8000), headers: { "content-type": "application/json" }, body: JSON.stringify({
      username: clip(username, 80), ...(avatarUrl ? { avatar_url: avatarUrl } : {}), allowed_mentions: { parse: [] }, embeds: [{ title, color: 0x43845b, fields: fields.slice(0, 10).map((field) => ({ ...field, name: clip(field.name, 256), value: clip(field.value, 1024) })), footer: { text: "DevReports · Notification d’équipe" }, timestamp: new Date().toISOString() }],
    }) });
  } catch {
    throw new PublicWebhookError("Connexion à Discord impossible ou expirée. Réessaie dans un instant.");
  }
  if (response.ok) return;
  if (response.status === 401 || response.status === 404) throw new PublicWebhookError("Discord ne reconnaît plus ce webhook. Recrée-le dans Discord puis remplace son URL dans Webhooks.");
  if (response.status === 403) throw new PublicWebhookError("Discord refuse l’accès à ce webhook. Vérifie que le salon et le webhook existent toujours.");
  if (response.status === 429) throw new PublicWebhookError("Discord limite temporairement les envois. Attends un peu puis réessaie.");
  throw new PublicWebhookError(`Discord a refusé le message (HTTP ${response.status}). Vérifie les réglages du webhook.`);
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") || "";
  if (!allowedOrigins.includes(origin)) return reply({ error: "Origine non autorisée." }, 403, origin);
  if (request.method === "OPTIONS") return reply({}, 200, origin);
  if (request.method !== "POST") return reply({ error: "Méthode non autorisée." }, 405, origin);
  try {
    if (!supabaseUrl || !serviceKey || !anonKey) return reply({ error: "Fonction serveur non configurée." }, 503, origin);
    const token = (request.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return reply({ error: "Connexion requise." }, 401, origin);
    const caller = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: auth, error: authError } = await caller.auth.getUser(token);
    if (authError || !auth.user) return reply({ error: "Session invalide ou expirée." }, 401, origin);
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from("profiles").select("role,status,display_name,nickname").eq("id", auth.user.id).single();
    if (profileError || profile?.status !== "active") return reply({ error: "Compte inactif ou profil indisponible." }, 403, origin);
    const isAdmin = profile.role === "admin";
    const body = await request.json();

    if (["get", "save", "delete", "test"].includes(body?.action)) {
      if (!isAdmin) return reply({ error: "Action réservée à un administrateur actif." }, 403, origin);
      if (body.action === "get") {
        const { data, error } = await admin.from("team_webhooks").select("id,name,username_mode,avatar_url,events,created_at,updated_at").order("created_at", { ascending: true });
        if (error) throw error;
        return reply({ webhooks: data || [] }, 200, origin);
      }
      const webhookId = typeof body.webhookId === "string" && /^[0-9a-f-]{36}$/i.test(body.webhookId) ? body.webhookId : "";
      if (body.action === "delete") {
        if (!webhookId) return reply({ error: "Webhook introuvable." }, 400, origin);
        const { error } = await admin.from("team_webhooks").delete().eq("id", webhookId);
        if (error) throw error;
        return reply({ ok: true }, 200, origin);
      }
      if (body.action === "save") {
        const name = typeof body.name === "string" ? body.name.trim() : "";
        const usernameMode = body.usernameMode === "named" ? "named" : body.usernameMode === "brand" ? "brand" : "";
        const avatarUrl = typeof body.avatarUrl === "string" ? body.avatarUrl.trim() : "";
        const url = typeof body.webhookUrl === "string" ? body.webhookUrl.trim() : "";
        const events = Array.isArray(body.events) ? [...new Set(body.events.filter((event: unknown) => typeof event === "string" && eventTypes.includes(event)))] : [];
        if (name.length < 2 || name.length > 80) return reply({ error: "Donne un nom de 2 à 80 caractères à ce webhook." }, 400, origin);
        if (!usernameMode) return reply({ error: "Choisis comment le nom du webhook doit apparaître dans Discord." }, 400, origin);
        if (avatarUrl && (avatarUrl.length > 2048 || !validAvatar(avatarUrl))) return reply({ error: "L’avatar doit être une URL HTTPS valide." }, 400, origin);
        if (!events.length) return reply({ error: "Sélectionne au moins un événement autorisé." }, 400, origin);
        if (url && (url.length > 2048 || !validWebhook(url))) return reply({ error: "URL refusée. Colle une URL de webhook Discord HTTPS valide." }, 400, origin);
        if (webhookId) {
          const { data: existing, error: existingError } = await admin.from("team_webhooks").select("id").eq("id", webhookId).maybeSingle();
          if (existingError) throw existingError;
          if (!existing) return reply({ error: "Ce webhook n’existe plus. Actualise la page." }, 404, origin);
          const values: Record<string, unknown> = { name, username_mode: usernameMode, avatar_url: avatarUrl || null, events, updated_at: new Date().toISOString() };
          if (url) values.webhook_url = url;
          const { error } = await admin.from("team_webhooks").update(values).eq("id", webhookId);
          if (error) throw error;
          return reply({ ok: true, updated: true, id: webhookId }, 200, origin);
        }
        if (!url) return reply({ error: "Colle l’URL du webhook Discord." }, 400, origin);
        const { count, error: countError } = await admin.from("team_webhooks").select("id", { count: "exact", head: true });
        if (countError) throw countError;
        if ((count || 0) >= 20) return reply({ error: "Limite de 20 webhooks atteinte." }, 400, origin);
        const { data: created, error } = await admin.from("team_webhooks").insert({ name, username_mode: usernameMode, avatar_url: avatarUrl || null, webhook_url: url, events, created_by: auth.user.id }).select("id").single();
        if (error) throw error;
        return reply({ ok: true, updated: false, id: created.id }, 200, origin);
      }
      if (!webhookId) return reply({ error: "Choisis le webhook à tester." }, 400, origin);
      const { data: config, error: configError } = await admin.from("team_webhooks").select("name,username_mode,avatar_url,webhook_url").eq("id", webhookId).maybeSingle();
      if (configError) throw configError;
      if (!config) return reply({ error: "Ce webhook n’existe plus. Actualise la page." }, 404, origin);
      await sendWebhook(config.webhook_url, config.username_mode === "brand" ? "DevReports" : `${config.name} | DevReports`, config.avatar_url, "Test DevReports", [{ name: "État", value: "La connexion Discord fonctionne." }, { name: "Envoyé par", value: clip(profile.nickname || profile.display_name, 150) }]);
      return reply({ ok: true }, 200, origin);
    }

    if (body?.action !== "notify" || !eventTypes.includes(body?.eventType) || typeof body.recordId !== "string" || !/^[0-9a-f-]{36}$/i.test(body.recordId)) return reply({ error: "Événement invalide." }, 400, origin);
    const eventType = body.eventType as string;
    const adminOnly = ["absence_recorded", "late_recorded", "warning_created", "announcement_published"].includes(eventType);
    if (adminOnly && !isAdmin) return reply({ error: "Action réservée à un administrateur." }, 403, origin);
    const { data: configs, error: configError } = await admin.from("team_webhooks").select("id,name,username_mode,avatar_url,webhook_url,events");
    if (configError) throw configError;
    const destinations = (configs || []).filter((config) => Array.isArray(config.events) && config.events.includes(eventType));
    if (!destinations.length) return reply({ ok: true, skipped: true }, 200, origin);

    const spec: Record<string, { table: string; columns: string }> = {
      report_created: { table: "reports", columns: "id,user_id,project,title,category,work,created_at" },
      absence_requested: { table: "team_absences", columns: "id,user_id,start_date,end_date,reason,status" },
      late_reported: { table: "late_notices", columns: "id,user_id,session_at,expected_delay_minutes,reason,status" },
      absence_recorded: { table: "team_absences", columns: "id,user_id,start_date,end_date,reason,status,absence_kind" },
      late_recorded: { table: "late_notices", columns: "id,user_id,session_at,expected_delay_minutes,reason,status,late_kind" },
      warning_created: { table: "member_warnings", columns: "id,member_id,admin_name,motif,description,created_at" },
      announcement_published: { table: "team_announcements", columns: "id,title,body,created_by,created_at" },
    };
    const { table, columns } = spec[eventType];
    const { data: row, error: rowError } = await admin.from(table).select(columns).eq("id", body.recordId).maybeSingle();
    if (rowError) throw rowError;
    if (!row) return reply({ error: "Événement introuvable." }, 404, origin);
    const ownerId = (row.user_id || row.created_by || row.admin_id || "") as string;
    if (ownerId !== auth.user.id && !isAdmin) return reply({ error: "Tu ne peux pas notifier cet événement." }, 403, origin);
    let memberName = "";
    const memberId = (row.user_id || row.member_id || "") as string;
    if (memberId) {
      const { data: member } = await admin.from("profiles").select("display_name,nickname").eq("id", memberId).maybeSingle();
      memberName = member?.nickname || member?.display_name || "Membre";
    }
    let fields: Array<{ name: string; value: string; inline?: boolean }> = [];
    if (eventType === "report_created") fields = [{ name: "Membre", value: memberName }, { name: "Projet", value: clip(row.project, 180), inline: true }, { name: "Catégorie", value: clip(row.category, 180), inline: true }, { name: "Rapport", value: clip(row.title, 220) }, { name: "Travail réalisé", value: clip(row.work, 900) }];
    else if (eventType === "absence_requested" || eventType === "absence_recorded") fields = [{ name: "Membre", value: memberName }, { name: "Période", value: `${row.start_date} → ${row.end_date}`, inline: true }, { name: "Statut", value: eventType === "absence_recorded" ? "Absence non justifiée consignée" : "Demande transmise", inline: true }, { name: "Motif / contexte", value: clip(row.reason) }];
    else if (eventType === "late_reported" || eventType === "late_recorded") fields = [{ name: "Membre", value: memberName }, { name: "Session", value: clip(row.session_at, 180), inline: true }, { name: "Durée", value: `${row.expected_delay_minutes} minutes`, inline: true }, { name: "Statut", value: eventType === "late_recorded" ? `Retard consigné (${row.late_kind || "non précisé"})` : "Retard signalé", inline: true }, { name: "Motif / contexte", value: clip(row.reason) }];
    else if (eventType === "warning_created") fields = [{ name: "Membre", value: memberName }, { name: "Attribué par", value: clip(row.admin_name, 180), inline: true }, { name: "Motif", value: clip(row.motif, 220) }, { name: "Description", value: clip(row.description) }];
    else fields = [{ name: "Titre", value: clip(row.title, 220) }, { name: "Annonce", value: clip(row.body) }];
    const outcomes = await Promise.all(destinations.map(async (config) => {
      const { error: deliveryError } = await admin.from("team_webhook_deliveries").insert({ webhook_id: config.id, event_type: eventType, record_id: body.recordId });
      if (deliveryError?.code === "23505") return { status: "duplicate" as const, name: config.name };
      if (deliveryError) throw deliveryError;
      try {
        await sendWebhook(config.webhook_url, config.username_mode === "brand" ? "DevReports" : `${config.name} | DevReports`, config.avatar_url, eventTitle(eventType), fields);
        return { status: "sent" as const, name: config.name };
      } catch (error) {
        await admin.from("team_webhook_deliveries").delete().eq("webhook_id", config.id).eq("event_type", eventType).eq("record_id", body.recordId);
        return { status: "failed" as const, name: config.name, error: error instanceof PublicWebhookError ? error.message : "Échec de livraison." };
      }
    }));
    return reply({ ok: true, sent: outcomes.filter((result) => result.status === "sent").length, skipped: outcomes.filter((result) => result.status === "duplicate").length, failed: outcomes.filter((result) => result.status === "failed").flatMap((result) => result.status === "failed" ? [{ name: result.name, error: result.error }] : []) }, 200, origin);
  } catch (error) {
    console.error("manage-team-webhook failed");
    if (error instanceof PublicWebhookError) return reply({ error: error.message }, 502, origin);
    return reply({ error: "Échec de l’opération webhook. Vérifie la configuration SQL, la fonction Supabase et le webhook Discord." }, 400, origin);
  }
});
