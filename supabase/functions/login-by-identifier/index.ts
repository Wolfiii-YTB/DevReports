import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
function projectKey(legacyName: string, currentName: string) {
  const legacy = Deno.env.get(legacyName);
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get(currentName) || "{}");
    return keys.default || Object.values(keys)[0] || "";
  } catch { return ""; }
}
const serviceKey = projectKey("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEYS");
const anonKey = projectKey("SUPABASE_ANON_KEY", "SUPABASE_PUBLISHABLE_KEYS");
const allowedOrigins = (Deno.env.get("ALLOWED_ORIGINS") || "").split(",").map((value) => value.trim()).filter(Boolean);

function reply(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), { status, headers: {
    "content-type": "application/json; charset=utf-8", "cache-control": "no-store, max-age=0",
    "x-content-type-options": "nosniff", "access-control-allow-origin": origin,
    "access-control-allow-headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
    "access-control-allow-methods": "POST, OPTIONS", "vary": "Origin",
  } });
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") || "";
  if (!allowedOrigins.length || !allowedOrigins.includes(origin)) return reply({ error: "Origine non autorisée." }, 403, "");
  if (request.method === "OPTIONS") return reply({}, 200, origin);
  if (request.method !== "POST") return reply({ error: "Méthode non autorisée." }, 405, origin);
  try {
    if (!supabaseUrl || !serviceKey || !anonKey) return reply({ error: "Fonction serveur non configurée." }, 503, origin);
    const body = await request.json();
    const identifier = typeof body?.identifier === "string" ? body.identifier.trim().toLowerCase() : "";
    const password = typeof body?.password === "string" ? body.password : "";
    if (!/^[a-z0-9][a-z0-9._-]{2,29}$/.test(identifier) || password.length < 1 || password.length > 128) {
      return reply({ error: "Identifiant ou mot de passe incorrect." }, 401, origin);
    }

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile } = await admin.from("profiles").select("id,status").eq("login_identifier", identifier).maybeSingle();
    if (!profile) return reply({ error: "Identifiant ou mot de passe incorrect." }, 401, origin);

    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(identifier));
    const hash = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
    const { data: allowed, error: rateError } = await admin.rpc("consume_identifier_login_attempt", { identifier_digest: hash });
    if (rateError) return reply({ error: "Connexion par identifiant temporairement indisponible." }, 503, origin);
    if (!allowed) return reply({ error: "Identifiant ou mot de passe incorrect." }, 401, origin);

    const { data: authUser, error: userError } = await admin.auth.admin.getUserById(profile.id);
    if (userError || !authUser.user?.email || authUser.user.email.endsWith("@devreports.invalid")) {
      return reply({ error: "Identifiant ou mot de passe incorrect." }, 401, origin);
    }
    const authResponse = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST", headers: { "content-type": "application/json", apikey: anonKey },
      body: JSON.stringify({ email: authUser.user.email, password }),
    });
    if (!authResponse.ok) return reply({ error: "Identifiant ou mot de passe incorrect." }, 401, origin);
    const session = await authResponse.json();
    await admin.rpc("clear_identifier_login_attempt", { identifier_digest: hash });
    return reply({ access_token: session.access_token, refresh_token: session.refresh_token, expires_in: session.expires_in, token_type: session.token_type }, 200, origin);
  } catch {
    return reply({ error: "Connexion indisponible. Réessaie." }, 400, origin);
  }
});
