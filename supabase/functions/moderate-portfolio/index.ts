import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://afwznqjpshybmqhlewmy.supabase.co";
const OPENAI_MODERATION_URL = "https://api.openai.com/v1/moderations";
const MODERATION_MODEL = "omni-moderation-latest";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ModerateBody {
  item_id?: string;
}

interface PortfolioItem {
  id: string;
  user_id: string;
  type: string;
  title: string | null;
  description: string | null;
  media_url: string | null;
  thumbnail_url: string | null;
  moderation_status: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!anonKey || !serviceKey) return json({ error: "missing_supabase_env" }, 500);

  const authHeader = req.headers.get("Authorization") || "";
  const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!accessToken) return json({ error: "not_authenticated" }, 401);

  const authClient = createClient(SUPABASE_URL, anonKey, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser(accessToken);
  if (userError || !userData.user) return json({ error: "not_authenticated" }, 401);

  let body: ModerateBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const itemId = body.item_id?.trim();
  if (!itemId) return json({ error: "missing_item_id" }, 400);

  const admin = createClient(SUPABASE_URL, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: item, error: itemError } = await admin
    .from("portfolio_items")
    .select("id,user_id,type,title,description,media_url,thumbnail_url,moderation_status")
    .eq("id", itemId)
    .single<PortfolioItem>();

  if (itemError || !item) return json({ error: "item_not_found" }, 404);
  if (item.user_id !== userData.user.id) return json({ error: "forbidden" }, 403);

  const decision = await moderateItem(item);
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
    .select("*");

  if (updateError) {
    return json({ error: "update_failed", detail: updateError.message }, 500);
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
  const text = [
    item.title ? `Название: ${item.title}` : "",
    item.description ? `Описание: ${item.description}` : "",
  ].filter(Boolean).join("\n").trim();

  if (item.type === "video") {
    const thumbnail = item.thumbnail_url?.trim();
    if (!thumbnail) {
      return {
        status: "manual_review",
        reason: "Видео ожидает ручную проверку",
        result: { reason: "video_without_thumbnail" },
        model: null,
        error: null,
      };
    }
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

    const result = payload?.results?.[0] ?? {};
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

function imageURLFor(item: PortfolioItem): string | null {
  const thumbnail = item.thumbnail_url?.trim();
  if (thumbnail) return thumbnail;
  if (item.type === "image") return item.media_url?.trim() || null;
  return null;
}

function reasonFor(categories: string[]): string {
  if (categories.includes("sexual/minors")) return "Материал отклонен: запрещенный сексуальный контент";
  if (categories.some((category) => category.startsWith("sexual"))) return "Материал отклонен: сексуальный контент";
  if (categories.some((category) => category.startsWith("violence"))) return "Материал отклонен: насилие";
  if (categories.some((category) => category.startsWith("hate"))) return "Материал отклонен: разжигание ненависти";
  if (categories.some((category) => category.startsWith("self-harm"))) return "Материал отклонен: самоповреждение";
  if (categories.some((category) => category.startsWith("illicit"))) return "Материал отклонен: запрещенная деятельность";
  if (categories.some((category) => category.startsWith("harassment"))) return "Материал отклонен: угрозы или травля";
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
