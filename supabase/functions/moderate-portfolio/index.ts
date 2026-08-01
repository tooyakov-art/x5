import { createClient } from "@supabase/supabase-js";
import {
  automaticPendingDecision,
  decisionFromModerationResult,
  MODERATION_MODEL,
} from "./decision.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ||
  "https://afwznqjpshybmqhlewmy.supabase.co";
const OPENAI_MODERATION_URL = "https://api.openai.com/v1/moderations";
const MAX_SWEEP_JOBS = 5;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ModerateBody {
  item_id?: string;
  action?: ModerationAction;
  moderation_revision?: number;
}

type ModerationAction = "moderate" | "retry";
// The project does not yet check in generated Supabase Database types.
// deno-lint-ignore no-explicit-any
type AdminClient = ReturnType<typeof createClient<any>>;

interface PortfolioItem {
  id: string;
  user_id: string;
  type: string;
  title: string | null;
  description: string | null;
  media_url: string | null;
  thumbnail_url: string | null;
  moderation_status: string;
  moderation_revision: number;
}

interface ModerationDecision {
  status: "approved" | "rejected" | "pending";
  reason: string;
  result: Record<string, unknown>;
  model: string | null;
  error: string | null;
}

interface ClaimedJob {
  status: "claimed";
  job_id: string;
  attempt: number;
  item: PortfolioItem;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!anonKey || !serviceKey) {
    return json({ error: "missing_supabase_env" }, 500);
  }

  const admin = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const isSweep = new URL(req.url).searchParams.get("sweep") === "1";
  if (isSweep) {
    const authorized = await hasValidSweepSecret(req);
    if (!authorized) return json({ error: "not_authenticated" }, 401);
    return runSweep(admin);
  }

  const accessToken = bearerToken(req);
  if (!accessToken) return json({ error: "not_authenticated" }, 401);
  const authClient = createClient(SUPABASE_URL, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser(
    accessToken,
  );
  if (userError || !userData.user) {
    return json({ error: "not_authenticated" }, 401);
  }

  let body: ModerateBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const itemId = body.item_id?.trim();
  if (!itemId) return json({ error: "missing_item_id" }, 400);
  const action: ModerationAction = body.action ?? "moderate";
  if (!(["moderate", "retry"] as string[]).includes(action)) {
    return json({ error: "invalid_action" }, 400);
  }
  const revision = body.moderation_revision;
  if (!Number.isSafeInteger(revision) || (revision ?? 0) < 1) {
    return json({ error: "invalid_moderation_revision" }, 400);
  }

  const leaseToken = randomLeaseToken();
  const { data: claimData, error: claimError } = await admin.rpc(
    "x5_claim_portfolio_moderation_job",
    {
      p_item_id: itemId,
      p_moderation_revision: revision,
      p_owner_id: userData.user.id,
      p_lease_token: leaseToken,
    },
  );
  if (claimError) {
    return json({ error: "claim_failed", detail: claimError.message }, 500);
  }
  const claim = claimData as Record<string, unknown> | null;
  if (claim?.status !== "claimed") return claimResponse(claim);

  const result = await processClaim(
    admin,
    claim as unknown as ClaimedJob,
    leaseToken,
  );
  return result.response;
});

async function runSweep(admin: AdminClient): Promise<Response> {
  const outcomes: Record<string, number> = {};
  let processed = 0;

  for (let index = 0; index < MAX_SWEEP_JOBS; index += 1) {
    const leaseToken = randomLeaseToken();
    const { data, error } = await admin.rpc(
      "x5_claim_next_portfolio_moderation_job",
      { p_lease_token: leaseToken },
    );
    if (error) {
      return json({ error: "sweep_claim_failed", detail: error.message }, 500);
    }
    const claim = data as Record<string, unknown> | null;
    if (!claim || claim.status === "empty") break;
    if (claim.status !== "claimed") {
      const status = String(claim.status ?? "unknown");
      outcomes[status] = (outcomes[status] ?? 0) + 1;
      continue;
    }

    const result = await processClaim(
      admin,
      claim as unknown as ClaimedJob,
      leaseToken,
    );
    processed += 1;
    outcomes[result.status] = (outcomes[result.status] ?? 0) + 1;
  }

  const cleanup = await cleanupPrivatePortfolioMedia(admin);
  return json({ ok: true, processed, outcomes, cleanup });
}

async function processClaim(
  admin: AdminClient,
  claim: ClaimedJob,
  leaseToken: string,
): Promise<{ status: string; response: Response }> {
  const decision = await moderateItem(admin, claim.item);
  const { data: completionData, error: completionError } = await admin.rpc(
    "x5_complete_portfolio_moderation_job",
    {
      p_job_id: claim.job_id,
      p_lease_token: leaseToken,
      p_status: decision.status,
      p_reason: decision.reason,
      p_result: decision.result,
      p_model: decision.model,
      p_error: decision.error,
    },
  );
  if (completionError) {
    return {
      status: "completion_failed",
      response: json({
        error: "completion_failed",
        detail: completionError.message,
      }, 500),
    };
  }

  const completion = completionData as Record<string, unknown> | null;
  const completionStatus = String(completion?.status ?? "unknown");
  if (
    !["completed", "retry_scheduled", "exhausted"].includes(
      completionStatus,
    )
  ) {
    return {
      status: completionStatus,
      response: json({ error: completionStatus }, 409),
    };
  }

  let cleanupError: string | null = null;
  if (decision.status === "rejected" && completionStatus === "completed") {
    cleanupError = await removeRejectedPortfolioMedia(admin, claim.item);
  }

  const { data: item } = await admin
    .from("portfolio_items")
    .select("*")
    .eq("id", claim.item.id)
    .eq("moderation_revision", claim.item.moderation_revision)
    .maybeSingle();

  return {
    status: completionStatus,
    response: json({
      ok: true,
      status: decision.status,
      queue_status: completionStatus,
      attempt: claim.attempt,
      retry_after: completion?.retry_after ?? null,
      cleanup_pending: cleanupError != null,
      item: item ?? null,
    }, completionStatus === "retry_scheduled" ? 202 : 200),
  };
}

async function moderateItem(
  admin: AdminClient,
  item: PortfolioItem,
): Promise<ModerationDecision> {
  if (hasInvalidPortfolioMediaURL(item)) {
    return {
      status: "rejected",
      reason: "Недопустимая ссылка на медиа портфолио",
      result: { reason: "portfolio_media_url_invalid" },
      model: null,
      error: null,
    };
  }

  const text = [
    item.title ? `Название: ${item.title}` : "",
    item.description ? `Описание: ${item.description}` : "",
  ].filter(Boolean).join("\n").trim();

  const imageUrl = await signedImageURLFor(admin, item);
  if (item.type === "video" && !imageUrl) {
    return automaticPendingDecision({
      code: "video_preview_missing",
      result: { reason: "video_preview_missing" },
      model: null,
      error: "video_preview_missing",
    });
  }
  if (!text && !imageUrl) {
    return automaticPendingDecision({
      code: "empty_content",
      result: { reason: "empty_content" },
      model: null,
      error: "empty_content",
    });
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return automaticPendingDecision({
      code: "missing_openai_key",
      result: { reason: "missing_openai_key" },
      model: MODERATION_MODEL,
      error: "missing_openai_key",
    });
  }

  const input: unknown[] = [];
  if (text) input.push({ type: "text", text });
  if (imageUrl) input.push({ type: "image_url", image_url: { url: imageUrl } });

  try {
    const response = await fetch(OPENAI_MODERATION_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ model: MODERATION_MODEL, input }),
      signal: AbortSignal.timeout(20_000),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      return automaticPendingDecision({
        code: "provider_unavailable",
        result: { openai_status: response.status, payload },
        model: MODERATION_MODEL,
        error: payload?.error?.message || `OpenAI ${response.status}`,
      });
    }
    return decisionFromModerationResult(
      payload?.results?.[0],
      payload,
      MODERATION_MODEL,
    );
  } catch (error) {
    return automaticPendingDecision({
      code: "provider_exception",
      result: { exception: String(error) },
      model: MODERATION_MODEL,
      error: String(error),
    });
  }
}

async function signedImageURLFor(
  admin: AdminClient,
  item: PortfolioItem,
): Promise<string | null> {
  const candidate = item.thumbnail_url?.trim() ||
    (item.type === "image" ? item.media_url?.trim() : null);
  if (!candidate) return null;
  const path = portfolioObjectPath(candidate, item.user_id);
  if (!path) return null;
  const { data, error } = await admin.storage
    .from("portfolio")
    .createSignedUrl(path, 300);
  if (error || !data?.signedUrl) return null;
  return data.signedUrl;
}

async function removeRejectedPortfolioMedia(
  admin: AdminClient,
  item: PortfolioItem,
): Promise<string | null> {
  const resolvedPaths = [item.media_url, item.thumbnail_url]
    .map((value) => value?.trim() || "")
    .filter(Boolean)
    .map((value) => portfolioObjectPath(value, item.user_id));
  if (resolvedPaths.some((value) => value == null)) {
    return "portfolio_media_path_invalid";
  }
  const paths = Array.from(
    new Set(resolvedPaths.filter((value): value is string => value != null)),
  );
  if (paths.length === 0) return null;
  const { error } = await admin.storage.from("portfolio").remove(paths);
  return error?.message ?? null;
}

async function cleanupPrivatePortfolioMedia(
  admin: AdminClient,
): Promise<{ removed: number; error?: string }> {
  const { data, error } = await admin.rpc("x5_list_portfolio_cleanup_paths", {
    p_limit: 100,
  });
  if (error) {
    // The cleanup RPC arrives in the immediately following private-storage
    // migration. A retry sweep will self-heal during a staged release.
    return { removed: 0, error: "cleanup_rpc_unavailable" };
  }
  const paths = Array.isArray(data?.paths)
    ? data.paths.filter((value: unknown): value is string =>
      typeof value === "string" && value.length > 0
    )
    : [];
  if (paths.length === 0) return { removed: 0 };
  const result = await admin.storage.from("portfolio").remove(paths);
  if (result.error) return { removed: 0, error: result.error.message };
  return { removed: paths.length };
}

function portfolioObjectPath(
  value: string,
  expectedOwnerId: string,
): string | null {
  const markers = [
    "/storage/v1/object/public/portfolio/",
    "/storage/v1/object/portfolio/",
  ];
  try {
    const parsed = new URL(value);
    if (parsed.origin !== new URL(SUPABASE_URL).origin) return null;
    if (parsed.username || parsed.password || parsed.search || parsed.hash) {
      return null;
    }
    const marker = markers.find((candidate) =>
      parsed.pathname.startsWith(candidate)
    );
    if (!marker) return null;
    const encodedPath = parsed.pathname.slice(marker.length);
    if (!encodedPath) return null;
    const decodedPath = decodeURIComponent(encodedPath);
    if (decodedPath.includes("\\")) return null;
    const segments = decodedPath.split("/");
    if (
      segments.length < 2 ||
      segments[0] !== expectedOwnerId ||
      segments.some((segment) =>
        !segment || segment === "." || segment === ".." ||
        segment.includes("\0")
      )
    ) {
      return null;
    }
    return segments.join("/");
  } catch {
    return null;
  }
}

function hasInvalidPortfolioMediaURL(item: PortfolioItem): boolean {
  return [item.media_url, item.thumbnail_url]
    .map((value) => value?.trim() || "")
    .filter(Boolean)
    .some((value) => portfolioObjectPath(value, item.user_id) == null);
}

function claimResponse(claim: Record<string, unknown> | null): Response {
  const status = String(claim?.status ?? "claim_failed");
  const retryAfter = Number(claim?.retry_after ?? 0);
  if (["in_progress", "not_due"].includes(status)) {
    const headers = Number.isFinite(retryAfter) && retryAfter > 0
      ? { "Retry-After": String(Math.ceil(retryAfter)) }
      : undefined;
    return json(
      { ok: true, queue_status: status, retry_after: retryAfter },
      202,
      headers,
    );
  }
  if (status === "not_found") return json({ error: status }, 404);
  if (status === "forbidden") return json({ error: status }, 403);
  if (
    ["stale_item", "completed", "already_completed", "exhausted", "superseded"]
      .includes(status)
  ) {
    return json({ error: status }, 409);
  }
  return json({ error: status }, 500);
}

async function hasValidSweepSecret(req: Request): Promise<boolean> {
  const expected =
    Deno.env.get("X5_PORTFOLIO_MODERATION_SWEEP_SECRET")?.trim() || "";
  const supplied =
    req.headers.get("X-X5-Portfolio-Moderation-Secret")?.trim() || "";
  if (expected.length < 32 || supplied.length < 32) return false;
  const encoder = new TextEncoder();
  const [expectedDigest, suppliedDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
    crypto.subtle.digest("SHA-256", encoder.encode(supplied)),
  ]);
  const left = new Uint8Array(expectedDigest);
  const right = new Uint8Array(suppliedDigest);
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function bearerToken(req: Request): string {
  return (req.headers.get("Authorization") || "")
    .replace(/^Bearer\s+/i, "")
    .trim();
}

function randomLeaseToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/,
    "",
  );
}

function json(
  payload: unknown,
  status = 200,
  extraHeaders?: Record<string, string>,
): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
  });
}
