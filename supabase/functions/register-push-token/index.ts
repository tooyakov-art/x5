import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://afwznqjpshybmqhlewmy.supabase.co";

interface RegisterBody {
  token?: string;
  platform?: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!serviceKey || !anonKey) return new Response("missing Supabase env", { status: 500 });

  const authHeader = req.headers.get("Authorization") || "";
  const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!accessToken) return new Response("missing token", { status: 401 });

  const authClient = createClient(SUPABASE_URL, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const { data: userData, error: userError } = await authClient.auth.getUser(accessToken);
  if (userError || !userData.user) return new Response("invalid user", { status: 401 });

  const body = (await req.json()) as RegisterBody;
  const token = normalizeAPNsToken(body.token);
  if (!token) return new Response("invalid APNs token", { status: 400 });

  const admin = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });
  const now = new Date().toISOString();
  const userId = userData.user.id;

  const { error: profileError } = await admin
    .from("profiles")
    .update({ push_token: token, push_token_updated_at: now })
    .eq("id", userId);
  if (profileError) return new Response(`profile update error: ${profileError.message}`, { status: 500 });

  const { error: tokenError } = await admin
    .from("push_tokens")
    .upsert(
      { user_id: userId, token, platform: "ios", updated_at: now },
      { onConflict: "user_id,platform" }
    );
  if (tokenError) return new Response(`token upsert error: ${tokenError.message}`, { status: 500 });

  return Response.json({ ok: true, updated_at: now });
});

function normalizeAPNsToken(raw: string | undefined): string | undefined {
  const trimmed = raw?.trim();
  if (!trimmed || trimmed.startsWith("ExponentPushToken")) return undefined;

  const compact = trimmed.replace(/[<>\s]/g, "").toLowerCase();
  if (/^[0-9a-f]+$/.test(compact) && compact.length >= 32) return compact;

  const bytes = trimmed.match(/bytes\s*=\s*0x([0-9a-fA-F\s]+)/i)?.[1];
  const normalizedBytes = bytes?.replace(/\s/g, "").toLowerCase();
  if (normalizedBytes && /^[0-9a-f]+$/.test(normalizedBytes) && normalizedBytes.length >= 32) {
    return normalizedBytes;
  }

  return undefined;
}
