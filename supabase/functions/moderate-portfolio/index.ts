import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ||
  "https://afwznqjpshybmqhlewmy.supabase.co";
const OPENAI_MODERATION_URL = "https://api.openai.com/v1/moderations";
const MODERATION_MODEL = "omni-moderation-latest";

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

type DeveloperAction = "approve" | "reject" | "retry";
type ModerationAction = "moderate" | DeveloperAction;

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

interface PortfolioStorageAdmin {
  storage: {
    from(bucketId: string): {
      remove(paths: string[]): Promise<{
        data: unknown;
        error: { message: string } | null;
      }>;
    };
  };
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

  const authHeader = req.headers.get("Authorization") || "";
  const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
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
  if (!["moderate", "approve", "reject", "retry"].includes(action)) {
    return json({ error: "invalid_action" }, 400);
  }

  const requiresDeveloper = action !== "moderate";
  const requestedRevision = body.moderation_revision;
  if (
    requestedRevision != null &&
    (!Number.isSafeInteger(requestedRevision) || requestedRevision < 1)
  ) {
    return json({ error: "invalid_moderation_revision" }, 400);
  }
  if (requestedRevision == null) {
    return json({ error: "missing_moderation_revision" }, 400);
  }

  let isDeveloper = false;
  if (requiresDeveloper) {
    const { data: developerData, error: developerError } = await authClient
      .rpc("is_x5_developer");
    isDeveloper = developerError == null && developerData === true;
  }
  if (requiresDeveloper && !isDeveloper) {
    return json({ error: "forbidden" }, 403);
  }

  const admin = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: item, error: itemError } = await admin
    .from("portfolio_items")
    .select(
      "id,user_id,type,title,description,media_url,thumbnail_url,moderation_status,moderation_revision",
    )
    .eq("id", itemId)
    .single<PortfolioItem>();

  if (itemError || !item) return json({ error: "item_not_found" }, 404);
  if (!requiresDeveloper && item.user_id !== userData.user.id) {
    return json({ error: "forbidden" }, 403);
  }
  if (
    requestedRevision != null &&
    requestedRevision !== item.moderation_revision
  ) {
    return json({ error: "stale_item" }, 409);
  }
  const queueStatuses = ["pending", "manual_review", "failed"];
  if (!requiresDeveloper && item.moderation_status !== "pending") {
    return json({ error: "stale_item" }, 409);
  }
  if (requiresDeveloper && !queueStatuses.includes(item.moderation_status)) {
    return json({ error: "stale_item" }, 409);
  }

  const decision = action === "approve" || action === "reject"
    ? developerDecision(action, userData.user.id)
    : await moderateItem(item);
  const update = {
    moderation_status: decision.status,
    moderation_reason: decision.reason,
    moderation_result: decision.result,
    moderation_model: decision.model,
    moderation_error: decision.error,
    moderated_at: new Date().toISOString(),
  };

  const { data: rows, error: updateError } = await admin
    .from("portfolio_items")
    .update(update)
    .eq("id", item.id)
    .eq("moderation_revision", item.moderation_revision)
    .eq("moderation_status", item.moderation_status)
    .select("*");

  if (updateError) {
    return json({ error: "update_failed", detail: updateError.message }, 500);
  }
  if (!rows || rows.length === 0) {
    return json({ error: "stale_item" }, 409);
  }
  const updatedItem = rows[0] as PortfolioItem;

  if (decision.status === "rejected") {
    const deletionError = await removeRejectedPortfolioMedia(admin, item);
    if (deletionError) {
      const { data: rollbackRows, error: rollbackError } = await admin
        .from("portfolio_items")
        .update({
          moderation_status: "manual_review",
          moderation_reason: "Не удалось безопасно удалить отклонённый файл",
          moderation_result: {
            ...decision.result,
            rejected_reason: decision.reason,
            media_cleanup_error: deletionError,
          },
          moderation_model: decision.model,
          moderation_error: deletionError,
          moderated_at: new Date().toISOString(),
        })
        .eq("id", item.id)
        .eq("moderation_revision", updatedItem.moderation_revision)
        .eq("moderation_status", "rejected")
        .select("id");
      if (rollbackError || !rollbackRows || rollbackRows.length === 0) {
        return json({
          error: "media_delete_failed_and_item_changed",
          detail: deletionError,
        }, 409);
      }
      return json({ error: "media_delete_failed", detail: deletionError }, 500);
    }
  }

  return json({
    ok: true,
    status: decision.status,
    reason: decision.reason,
    item: rows?.[0] ?? null,
  });
});

async function moderateItem(item: PortfolioItem): Promise<{
  status: "approved" | "rejected" | "manual_review" | "failed";
  reason: string;
  result: Record<string, unknown>;
  model: string | null;
  error: string | null;
}> {
  if (hasInvalidPortfolioMediaURL(item)) {
    return {
      status: "failed",
      reason: "Недопустимая ссылка на медиа портфолио",
      result: { reason: "portfolio_media_url_invalid" },
      model: null,
      error: "portfolio_media_url_invalid",
    };
  }

  const text = [
    item.title ? `Название: ${item.title}` : "",
    item.description ? `Описание: ${item.description}` : "",
  ].filter(Boolean).join("\n").trim();

  if (item.type === "video") {
    return {
      status: "manual_review",
      reason: "Видео ожидает проверки разработчиком",
      result: { reason: "video_requires_developer_review" },
      model: null,
      error: null,
    };
  }

  const imageUrl = imageURLFor(item);
  if (!text && !imageUrl) {
    return {
      status: "manual_review",
      reason: "Недостаточно данных для автоматической проверки",
      result: { reason: "empty_content" },
      model: null,
      error: null,
    };
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return {
      status: "manual_review",
      reason: "Автомодерация не настроена",
      result: { reason: "missing_openai_key" },
      model: MODERATION_MODEL,
      error: "missing_openai_key",
    };
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
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      return {
        status: "manual_review",
        reason: "Не удалось проверить автоматически",
        result: { openai_status: response.status, payload },
        model: MODERATION_MODEL,
        error: payload?.error?.message || `OpenAI ${response.status}`,
      };
    }

    const result = payload?.results?.[0];
    if (
      !result ||
      typeof result.flagged !== "boolean" ||
      !result.categories ||
      typeof result.categories !== "object"
    ) {
      return {
        status: "manual_review",
        reason: "Ответ автоматической проверки неоднозначен",
        result: { reason: "moderation_response_invalid", payload },
        model: MODERATION_MODEL,
        error: "moderation_response_invalid",
      };
    }

    const flagged = result?.flagged === true;
    const categories = result?.categories ?? {};
    const flaggedCategories = Object.entries(categories)
      .filter(([, value]) => value === true)
      .map(([key]) => key);

    if (flagged || flaggedCategories.length > 0) {
      return {
        status: "rejected",
        reason: reasonFor(flaggedCategories),
        result: payload,
        model: MODERATION_MODEL,
        error: null,
      };
    }

    return {
      status: "approved",
      reason: "Проверено автоматически",
      result: payload,
      model: MODERATION_MODEL,
      error: null,
    };
  } catch (error) {
    return {
      status: "manual_review",
      reason: "Не удалось проверить автоматически",
      result: { exception: String(error) },
      model: MODERATION_MODEL,
      error: String(error),
    };
  }
}

async function removeRejectedPortfolioMedia(
  admin: PortfolioStorageAdmin,
  item: PortfolioItem,
): Promise<string | null> {
  const mediaURLs = [item.media_url, item.thumbnail_url]
    .map((value) => value?.trim() || "")
    .filter(Boolean);
  const resolvedPaths = mediaURLs.map((value) =>
    portfolioObjectPath(value, item.user_id)
  );

  if (resolvedPaths.some((value) => value == null)) {
    return "portfolio_media_path_invalid";
  }
  const objectPaths = Array.from(
    new Set(resolvedPaths.filter((value): value is string => value != null)),
  );
  if (objectPaths.length === 0) return null;

  const { error } = await admin.storage.from("portfolio").remove(objectPaths);
  return error?.message ?? null;
}

function portfolioObjectPath(
  value: string,
  expectedOwnerId: string,
): string | null {
  const marker = "/storage/v1/object/public/portfolio/";
  try {
    const parsed = new URL(value);
    const expectedOrigin = new URL(SUPABASE_URL).origin;
    if (parsed.origin !== expectedOrigin) return null;
    if (parsed.username || parsed.password) return null;
    if (parsed.search || parsed.hash) return null;
    if (!parsed.pathname.startsWith(marker)) return null;
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

function developerDecision(
  action: Exclude<DeveloperAction, "retry">,
  developerUserId: string,
): {
  status: "approved" | "rejected";
  reason: string;
  result: Record<string, unknown>;
  model: string;
  error: null;
} {
  const approved = action === "approve";
  return {
    status: approved ? "approved" : "rejected",
    reason: approved ? "Одобрено разработчиком" : "Отклонено разработчиком",
    result: {
      action,
      developer_user_id: developerUserId,
      reviewed_at: new Date().toISOString(),
    },
    model: "developer-review",
    error: null,
  };
}

function imageURLFor(item: PortfolioItem): string | null {
  const thumbnail = item.thumbnail_url?.trim();
  if (thumbnail && portfolioObjectPath(thumbnail, item.user_id)) {
    return thumbnail;
  }
  const media = item.media_url?.trim();
  if (
    item.type === "image" &&
    media &&
    portfolioObjectPath(media, item.user_id)
  ) {
    return media;
  }
  return null;
}

function reasonFor(categories: string[]): string {
  if (categories.includes("sexual/minors")) {
    return "Материал отклонен: запрещенный сексуальный контент";
  }
  if (categories.some((category) => category.startsWith("sexual"))) {
    return "Материал отклонен: сексуальный контент";
  }
  if (categories.some((category) => category.startsWith("violence"))) {
    return "Материал отклонен: насилие";
  }
  if (categories.some((category) => category.startsWith("hate"))) {
    return "Материал отклонен: разжигание ненависти";
  }
  if (categories.some((category) => category.startsWith("self-harm"))) {
    return "Материал отклонен: самоповреждение";
  }
  if (categories.some((category) => category.startsWith("illicit"))) {
    return "Материал отклонен: запрещенная деятельность";
  }
  if (categories.some((category) => category.startsWith("harassment"))) {
    return "Материал отклонен: угрозы или травля";
  }
  return "Материал отклонен автоматической модерацией";
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
