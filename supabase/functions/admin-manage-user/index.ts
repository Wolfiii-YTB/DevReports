import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
function getProjectKey(legacyName: string, currentName: string) {
  const legacy = Deno.env.get(legacyName);
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get(currentName) || "{}");
    return keys.default || Object.values(keys)[0] || "";
  } catch {
    return "";
  }
}
const serviceKey = getProjectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS");
const anonKey = getProjectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS");
const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") || "").split(",").map((value) => value.trim()).filter(Boolean);

function response(body: unknown, status = 200, origin = "") {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": origin,
      "access-control-allow-headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
      "access-control-allow-methods": "POST, OPTIONS",
      "vary": "Origin",
    },
  });
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") || "";
  if (!allowedOrigins.length || !allowedOrigins.includes(origin)) return response({ error: "Origine non autorisée." }, 403);
  if (request.method === "OPTIONS") return response({}, 200, origin);
  if (request.method !== "POST") return response({ error: "Méthode non autorisée." }, 405, origin);

  try {
    if (!supabaseUrl || !serviceKey || !anonKey) return response({ error: "Fonction serveur non configurée." }, 503, origin);
    const authorization = request.headers.get("authorization") || "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token) return response({ error: "Connexion requise." }, 401, origin);

    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    if (authError || !authData.user) return response({ error: "Session invalide ou expirée." }, 401, origin);

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: callerProfile, error: profileError } = await admin.from("profiles").select("role,status").eq("id", authData.user.id).single();
    if (profileError || callerProfile?.role !== "admin" || callerProfile?.status !== "active") {
      return response({ error: "Action réservée à un administrateur actif." }, 403, origin);
    }

    const body = await request.json();
    if (body?.action === "listUsers") {
      const [{ data: profiles, error: profilesError }, users] = await Promise.all([
        admin.from("profiles").select("id,display_name,nickname,role,roles,status"),
        admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
      ]);
      if (profilesError) throw profilesError;
      if (users.error) throw users.error;
      const profileById = new Map<string, Record<string, unknown>>((profiles || []).map((profile) => [profile.id, profile] as [string, Record<string, unknown>]));
      const rows = (users.data.users || []).map((user) => ({
        id: user.id,
        email: user.email?.endsWith("@devreports.invalid") ? "" : user.email || "",
        loginIdentifier: typeof user.user_metadata?.login_identifier === "string" ? user.user_metadata.login_identifier : "",
        ...(profileById.get(user.id) || {}),
      }));
      return response({ users: rows }, 200, origin);
    }

    if (body?.action === "createIdentifierUser") {
      const displayName = typeof body.displayName === "string" ? body.displayName.trim() : "";
      const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";
      const identifier = typeof body.identifier === "string" ? body.identifier.trim().toLowerCase() : "";
      if (displayName.length < 2 || displayName.length > 80 || nickname.length > 40) return response({ error: "Le nom ou le pseudo est invalide." }, 400, origin);
      if (!/^[a-z0-9][a-z0-9._-]{2,29}$/.test(identifier)) return response({ error: "Identifiant invalide : 3 à 30 caractères, lettres sans accent, chiffres, point, tiret ou tiret bas." }, 400, origin);
      const temporaryPassword = Array.from(crypto.getRandomValues(new Uint8Array(24)), (byte) => byte.toString(16).padStart(2, "0")).join("");
      const internalEmail = `id-${identifier}@devreports.invalid`;
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: internalEmail,
        password: temporaryPassword,
        email_confirm: true,
        user_metadata: { display_name: displayName, nickname, login_identifier: identifier, must_change_password: true },
      });
      if (createError) {
        if (createError.message.toLowerCase().includes("already") || createError.message.toLowerCase().includes("registered")) return response({ error: "Cet identifiant est déjà pris. Choisis-en un autre." }, 409, origin);
        throw createError;
      }
      const { error: profileUpdateError } = await admin.from("profiles").update({ display_name: displayName, nickname, role: "developer", roles: ["developer"], status: "active" }).eq("id", created.user.id);
      if (profileUpdateError) {
        await admin.auth.admin.deleteUser(created.user.id);
        throw profileUpdateError;
      }
      return response({ ok: true, identifier, temporaryPassword }, 201, origin);
    }

    if (body?.action !== "updateUser" || typeof body.userId !== "string") {
      return response({ error: "Requête invalide." }, 400, origin);
    }
    const userId = body.userId;
    const { data: primaryAdmin } = await admin.from("profiles").select("id").eq("role", "admin").order("created_at", { ascending: true }).limit(1).maybeSingle();
    if (primaryAdmin?.id === userId && primaryAdmin.id !== authData.user.id) {
      return response({ error: "Le compte administrateur principal ne peut être modifié que par son propriétaire." }, 403, origin);
    }
    const displayName = typeof body.displayName === "string" ? body.displayName.trim() : "";
    const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (displayName.length < 2 || displayName.length > 80 || nickname.length > 40) {
      return response({ error: "Le nom doit contenir 2 à 80 caractères et le pseudo 40 au maximum." }, 400, origin);
    }
    if (email && (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
      return response({ error: "Adresse e-mail invalide." }, 400, origin);
    }
    if (password && password.length < 8) return response({ error: "Le mot de passe doit contenir au moins 8 caractères." }, 400, origin);
    if (password.length > 128) return response({ error: "Mot de passe trop long." }, 400, origin);

    const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(userId);
    if (targetError || !targetData.user) return response({ error: "Compte introuvable." }, 404, origin);
    const emailChanged = Boolean(email && email.toLowerCase() !== (targetData.user.email || "").toLowerCase());
    if (primaryAdmin?.id === userId && (emailChanged || password)) {
      return response({ error: "Le mot de passe et l’adresse du compte administrateur principal sont verrouillés." }, 403, origin);
    }
    const updates: Record<string, unknown> = { user_metadata: { ...(targetData.user.user_metadata || {}), display_name: displayName, nickname } };
    if (targetData.user.user_metadata?.login_identifier && emailChanged) return response({ error: "L’adresse technique de connexion par identifiant ne peut pas être modifiée." }, 403, origin);
    if (emailChanged) updates.email = email;
    if (password) updates.password = password;
    const { error: updateError } = await admin.auth.admin.updateUserById(userId, updates);
    if (updateError) throw updateError;
    const { error: profileUpdateError } = await admin.from("profiles").update({ display_name: displayName, nickname }).eq("id", userId);
    if (profileUpdateError) throw profileUpdateError;
    return response({ ok: true, emailChanged, passwordChanged: Boolean(password) }, 200, origin);
  } catch (error) {
    console.error("admin-manage-user failed");
    return response({ error: "La modification du compte a échoué. Vérifie l’adresse, la migration et la configuration de la fonction." }, 400, origin);
  }
});
