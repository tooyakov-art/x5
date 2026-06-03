// Supabase Edge Function: send-message-push
//
// Triggered by a Postgres webhook on INSERT into the `messages` table.
// Reads the chat row to find the recipient (the participant that's not the sender),
// reads recipient's push_token from `profiles`, and sends an APNs push.
//
// Required env (set via `supabase secrets set`):
//   APNS_KEY_ID             -- the AuthKey ID (e.g. "ABC123XYZ4")
//   APNS_TEAM_ID            -- Apple Developer team id (e.g. "F8LA8PC4U6")
//   APNS_BUNDLE_ID          -- "com.x5studio.app"
//   APNS_PRIVATE_KEY        -- contents of AuthKey_<KEY_ID>.p8 (PEM with -----BEGIN/END PRIVATE KEY-----)
//   APNS_USE_SANDBOX        -- "1" for debug/dev APNs tokens, "0" for TestFlight/App Store
//
// Auto-injected by the Supabase Edge runtime (we cannot set SUPABASE_*
// secrets manually — the prefix is reserved):
//   SUPABASE_SERVICE_ROLE_KEY  -- service-role key for reading profiles/chats
//   SUPABASE_URL               -- project URL
//
// Postgres trigger to install once (run in SQL editor):
//
//   create extension if not exists pg_net;
//
//   create or replace function notify_new_message() returns trigger
//   language plpgsql security definer as $$
//   begin
//     perform net.http_post(
//       url := 'https://afwznqjpshybmqhlewmy.functions.supabase.co/send-message-push',
//       headers := jsonb_build_object(
//         'Content-Type', 'application/json',
//         'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
//       ),
//       body := to_jsonb(NEW)
//     );
//     return NEW;
//   end;
//   $$;
//
//   drop trigger if exists messages_push_notify on messages;
//   create trigger messages_push_notify after insert on messages
//     for each row execute function notify_new_message();

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create as jwtCreate, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const SUPABASE_URL = "https://afwznqjpshybmqhlewmy.supabase.co";

const APNS_HOST_PROD = "https://api.push.apple.com";
const APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com";

interface MessageRow {
  id: string;
  chat_id: string;
  sender_id: string;
  type: string;
  content: string | null;
}

type IncomingPayload = Partial<MessageRow> & {
  record?: MessageRow;
  new?: MessageRow;
};

interface ChatRow {
  id: string;
  participants: string[];
  task_title: string | null;
}

interface SocialPushPayload {
  recipient_id: string;
  actor_id: string;
  type: string;
  title?: string;
  body?: string;
  object_type?: string;
  object_id?: string;
  thread_id?: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  // Supabase reserves the SUPABASE_ prefix for secrets — the runtime
  // provides SUPABASE_SERVICE_ROLE_KEY automatically.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) return new Response("missing service role key", { status: 500 });
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || SUPABASE_URL;
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const rawJson = (await req.json()) as IncomingPayload | SocialPushPayload;
  if (isSocialPushPayload(rawJson)) {
    return await sendSocialPush(supabase, rawJson);
  }

  const raw = rawJson as IncomingPayload;
  const body = raw.record ?? raw.new ?? (raw as MessageRow);
  if (!body?.chat_id || !body.sender_id) {
    return new Response("bad request", { status: 400 });
  }

  // Look up chat to find the other participant
  const { data: chat, error: chatError } = await supabase
    .from("chats")
    .select("id, participants, task_title")
    .eq("id", body.chat_id)
    .maybeSingle<ChatRow>();

  if (chatError) return new Response(`chat lookup error: ${chatError.message}`, { status: 500 });
  if (!chat) return new Response("chat not found", { status: 404 });

  const recipient = chat.participants.find((p) => p !== body.sender_id);
  if (!recipient) return new Response("no recipient", { status: 200 });

  // Look up sender for notification title and recipient token for APNs.
  const [{ data: sender }, tokenLookup] = await Promise.all([
    supabase.from("profiles").select("name, nickname").eq("id", body.sender_id).maybeSingle(),
    loadAPNsToken(supabase, recipient)
  ]);

  if (tokenLookup.error) return new Response(`token lookup error: ${tokenLookup.error}`, { status: 500 });
  if (!tokenLookup.token) return new Response("no push token", { status: 200 });

  const senderName: string = (sender?.name as string) || (sender?.nickname as string) || "X5";

  const previewBody =
    body.type === "text"
      ? (body.content || "Новое сообщение")
      : body.type === "image" ? "Фото" : body.type === "audio" ? "Голосовое" : "Новое сообщение";

  const payload = {
    aps: {
      alert: {
        title: chat.task_title || senderName,
        subtitle: chat.task_title ? senderName : undefined,
        body: previewBody
      },
      sound: "default",
      badge: 1,
      "thread-id": chat.id,
      category: "MESSAGE"
    },
    chat_id: chat.id,
    sender_id: body.sender_id
  };

  return await sendAPNs(tokenLookup.token, payload);
});

function isSocialPushPayload(value: IncomingPayload | SocialPushPayload): value is SocialPushPayload {
  const payload = value as SocialPushPayload;
  return Boolean(payload.recipient_id && payload.actor_id && payload.type);
}

async function sendSocialPush(supabase: any, body: SocialPushPayload): Promise<Response> {
  if (body.recipient_id === body.actor_id) return new Response("self event ignored");

  const [{ data: actor }, tokenLookup] = await Promise.all([
    supabase.from("profiles").select("name, nickname").eq("id", body.actor_id).maybeSingle(),
    loadAPNsToken(supabase, body.recipient_id)
  ]);

  if (tokenLookup.error) return new Response(`token lookup error: ${tokenLookup.error}`, { status: 500 });
  if (!tokenLookup.token) return new Response("no push token", { status: 200 });

  const actorName: string = (actor?.name as string) || (actor?.nickname as string) || "X5";
  const title = body.title || actorName;
  const text = body.body || defaultSocialBody(body.type, actorName);

  const payload = {
    aps: {
      alert: {
        title,
        body: text
      },
      sound: "default",
      badge: 1,
      "thread-id": body.thread_id || body.object_id || body.type,
      category: "SOCIAL"
    },
    type: body.type,
    actor_id: body.actor_id,
    object_type: body.object_type,
    object_id: body.object_id
  };

  return await sendAPNs(tokenLookup.token, payload);
}

async function loadAPNsToken(
  supabase: any,
  userId: string
): Promise<{ token?: string; error?: string }> {
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("push_token")
    .eq("id", userId)
    .maybeSingle();

  if (profileError) return { error: profileError.message };

  const profileToken = cleanAPNsToken(profile?.push_token as string | undefined);
  if (profileToken) return { token: profileToken };

  const { data: legacyRows, error: legacyError } = await supabase
    .from("push_tokens")
    .select("token, updated_at")
    .eq("user_id", userId)
    .eq("platform", "ios")
    .order("updated_at", { ascending: false })
    .limit(1);

  if (legacyError) return { error: legacyError.message };

  return { token: cleanAPNsToken(legacyRows?.[0]?.token as string | undefined) };
}

function cleanAPNsToken(token: string | undefined): string | undefined {
  const trimmed = token?.trim();
  if (!trimmed || trimmed.startsWith("ExponentPushToken")) return undefined;
  return trimmed;
}

function defaultSocialBody(type: string, actorName: string): string {
  switch (type) {
    case "portfolio_like":
      return `${actorName} liked your case`;
    case "followed_user_posted":
      return `${actorName} posted in X5`;
    default:
      return `${actorName} has an update`;
  }
}

async function sendAPNs(pushToken: string, payload: unknown): Promise<Response> {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !bundleId || !pem) {
    return new Response("missing APNs env", { status: 500 });
  }

  const cryptoKey = await importPKCS8(pem);
  const jwt = await jwtCreate(
    { alg: "ES256", kid: keyId, typ: "JWT" },
    { iss: teamId, iat: getNumericDate(0) },
    cryptoKey
  );

  const firstHost = preferredAPNsHost();
  let apnsRes = await sendAPNsToHost(firstHost, pushToken, payload, jwt, bundleId);

  if (!apnsRes.ok) {
    const firstText = await apnsRes.text();
    const shouldRetryOppositeHost =
      apnsRes.status === 400
      && firstText.includes("BadDeviceToken")
      && Deno.env.get("APNS_ENV") !== "production"
      && Deno.env.get("APNS_ENV") !== "sandbox";

    if (shouldRetryOppositeHost) {
      const retryHost = firstHost === APNS_HOST_PROD ? APNS_HOST_SANDBOX : APNS_HOST_PROD;
      apnsRes = await sendAPNsToHost(retryHost, pushToken, payload, jwt, bundleId);
      if (apnsRes.ok) return new Response(`ok via ${hostLabel(retryHost)}`);
      const retryText = await apnsRes.text();
      return new Response(
        `APNs error ${hostLabel(firstHost)} ${firstText}; retry ${hostLabel(retryHost)} ${apnsRes.status}: ${retryText}`,
        { status: 502 }
      );
    }

    return new Response(`APNs error ${hostLabel(firstHost)} ${apnsRes.status}: ${firstText}`, { status: 502 });
  }
  return new Response(`ok via ${hostLabel(firstHost)}`);
}

function preferredAPNsHost(): string {
  const explicit = Deno.env.get("APNS_ENV");
  if (explicit === "sandbox") return APNS_HOST_SANDBOX;
  if (explicit === "production") return APNS_HOST_PROD;
  return (Deno.env.get("APNS_USE_SANDBOX") || "0") === "1" ? APNS_HOST_SANDBOX : APNS_HOST_PROD;
}

function hostLabel(host: string): string {
  return host === APNS_HOST_SANDBOX ? "sandbox" : "production";
}

async function sendAPNsToHost(
  host: string,
  pushToken: string,
  payload: unknown,
  jwt: string,
  bundleId: string
): Promise<Response> {
  return await fetch(`${host}/3/device/${pushToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    },
    body: JSON.stringify(payload)
  });
}

async function importPKCS8(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}
