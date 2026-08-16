import { handleCreateCourseVideoUpload } from "./handler.mjs";

const AUTH_TIMEOUT_MS = 6_000;
const RPC_TIMEOUT_MS = 4_000;
// Release quarantine: Bunny playback is not entitlement-protected and the
// readiness/moderation/cleanup lifecycle is unfinished. Keep this source
// deploy-safe even if the function or database migration is applied by mistake.
const BUNNY_COURSE_VIDEO_UPLOAD_RELEASE_ENABLED = false;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const response = await handleCreateCourseVideoUpload(request, {
    releaseEnabled: BUNNY_COURSE_VIDEO_UPLOAD_RELEASE_ENABLED,
    env: {
      BUNNY_STREAM_LIBRARY_ID: Deno.env.get("BUNNY_STREAM_LIBRARY_ID"),
      BUNNY_STREAM_API_KEY: Deno.env.get("BUNNY_STREAM_API_KEY"),
      BUNNY_STREAM_CDN_HOSTNAME: Deno.env.get(
        "BUNNY_STREAM_CDN_HOSTNAME",
      ),
      BUNNY_STREAM_TUS_TTL_SECONDS: Deno.env.get(
        "BUNNY_STREAM_TUS_TTL_SECONDS",
      ),
    },
    now: () => Date.now(),
    verifyUser,
    isDeveloper,
    claimUpload,
    completeUpload,
    fetchImpl: fetch,
    randomUUID: () => crypto.randomUUID(),
    logger: console,
  });

  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(corsHeaders)) {
    headers.set(name, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
});

async function verifyUser(
  authorization: string,
): Promise<{ id?: string } | null> {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !anonKey) return null;

  try {
    const response = await fetch(`${supabaseURL}/auth/v1/user`, {
      headers: {
        apikey: anonKey,
        Authorization: authorization,
      },
      signal: AbortSignal.timeout(AUTH_TIMEOUT_MS),
    });
    if (!response.ok) return null;
    const payload: unknown = await response.json().catch(() => null);
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return null;
    }
    return payload as { id?: string };
  } catch {
    return null;
  }
}

async function isDeveloper(authorization: string): Promise<boolean> {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !anonKey) return false;

  try {
    const response = await fetch(
      `${supabaseURL}/rest/v1/rpc/is_x5_developer`,
      {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: "{}",
        signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
      },
    );
    if (!response.ok) return false;
    return await response.json().catch(() => false) === true;
  } catch {
    return false;
  }
}

type UploadClaimInput = {
  purpose: string;
  uploadKey: string;
  resourceID: string;
  requestFingerprint: string;
  leaseToken: string;
};

type UploadCompletionInput = {
  uploadKey: string;
  requestFingerprint: string;
  leaseToken: string;
  videoID: string;
};

async function claimUpload(
  authorization: string,
  input: UploadClaimInput,
): Promise<Record<string, unknown> | null> {
  return await callUserRPC(
    "claim_course_video_upload_slot",
    {
      p_upload_key: input.uploadKey,
      p_purpose: input.purpose,
      p_resource_id: input.resourceID,
      p_request_fingerprint: input.requestFingerprint,
      p_lease_token: input.leaseToken,
    },
    authorization,
  );
}

async function completeUpload(
  authorization: string,
  input: UploadCompletionInput,
): Promise<Record<string, unknown> | null> {
  return await callUserRPC(
    "complete_course_video_upload_slot",
    {
      p_upload_key: input.uploadKey,
      p_request_fingerprint: input.requestFingerprint,
      p_lease_token: input.leaseToken,
      p_video_id: input.videoID,
    },
    authorization,
  );
}

async function callUserRPC(
  name: string,
  parameters: Record<string, unknown>,
  authorization: string,
): Promise<Record<string, unknown> | null> {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !anonKey) return null;

  try {
    const response = await fetch(
      `${supabaseURL}/rest/v1/rpc/${encodeURIComponent(name)}`,
      {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: authorization,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(parameters),
        signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
      },
    );
    if (!response.ok) return null;
    const payload: unknown = await response.json().catch(() => null);
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return null;
    }
    return payload as Record<string, unknown>;
  } catch {
    return null;
  }
}
