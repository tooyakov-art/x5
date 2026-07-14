// Supabase Edge Function: generate-image
//
// Required env:
//   OPENAI_API_KEY
//   GOOGLE_API_KEY or GEMINI_API_KEY
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY

import {
  buildFinalPrompt,
  extractGoogleErrorMessage,
  extractGoogleImageData,
  GenerationRequestError,
  googleResponseFormat,
  hasUsableGenerationProvider,
  normalizeGenerationRequest,
  normalizeProviderKeys,
  safeProviderErrorMessage,
  shouldFallbackGoogleToGPT,
  shouldRetryGoogleWithNextKey,
} from "./economy.mjs";

const OPENAI_URL = "https://api.openai.com/v1/images/generations";
const OPENAI_EDIT_URL = "https://api.openai.com/v1/images/edits";
const GOOGLE_INTERACTIONS_URL =
  "https://generativelanguage.googleapis.com/v1beta/interactions";
const GOOGLE_MODEL = "gemini-3.1-flash-image";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") || "";
  if (!auth.startsWith("Bearer ")) {
    return json({ error: "not_authenticated" }, 401);
  }

  const user = await verifyUser(auth);
  if (!user?.id) {
    return json({ error: "not_authenticated" }, 401);
  }

  let normalized;
  try {
    normalized = normalizeGenerationRequest(await req.json());
  } catch (error) {
    if (error instanceof GenerationRequestError) {
      return json({ error: error.code }, error.status);
    }
    return json({ error: "invalid_json" }, 400);
  }

  const providerKeys = getProviderKeys(normalized.provider);
  const fallbackOpenAIKey = normalized.provider === "google"
    ? getProviderKeys("gpt")[0]
    : undefined;
  if (
    !hasUsableGenerationProvider(
      normalized.provider,
      providerKeys.length,
      fallbackOpenAIKey ? 1 : 0,
    )
  ) {
    return json({
      error: "provider_not_configured",
      provider: normalized.provider,
      message: normalized.provider === "google"
        ? "Google Gemini API key is not configured."
        : "Image provider API key is not configured.",
    }, 503);
  }

  const spent = await spendCredits(user.id, normalized.costCredits);
  if (!spent.ok) {
    return json(
      {
        error: spent.error,
        creditsRequired: normalized.costCredits,
        creditsRemaining: spent.credits ?? 0,
      },
      spent.status,
    );
  }

  try {
    const finalPrompt = buildFinalPrompt(
      normalized.prompt,
      normalized.category,
      normalized.images.length > 0,
    );
    let responseProvider = normalized.provider;
    let responseModel = normalized.model;
    let fallbackFrom: string | undefined;
    let imageBase64s: string[];

    if (normalized.provider === "google" && providerKeys.length === 0) {
      if (!fallbackOpenAIKey) {
        throw new Error("No image provider is configured");
      }
      console.warn(JSON.stringify({
        event: "google_image_fallback",
        google_status: 503,
        google_reason: "provider_not_configured",
        requested_model: normalized.model,
        fallback_provider: "gpt",
      }));
      imageBase64s = await generateWithGPT(
        fallbackOpenAIKey,
        finalPrompt,
        "gpt-image-2",
        normalized.images,
        normalized.quantity,
        normalized.size,
      );
      responseProvider = "gpt";
      responseModel = "gpt-image-2";
      fallbackFrom = "google";
    } else if (normalized.provider === "google") {
      try {
        imageBase64s = await generateWithGoogle(
          providerKeys,
          finalPrompt,
          normalized.model,
          normalized.images,
          normalized.quantity,
          normalized.size,
        );
      } catch (googleError) {
        const googleStatus = Number(
          googleError instanceof Error && "status" in googleError
            ? (googleError as Error & { status?: number }).status || 503
            : 503,
        );
        if (!fallbackOpenAIKey || !shouldFallbackGoogleToGPT(googleStatus)) {
          throw googleError;
        }

        console.warn(JSON.stringify({
          event: "google_image_fallback",
          google_status: googleStatus,
          requested_model: normalized.model,
          fallback_provider: "gpt",
        }));
        imageBase64s = await generateWithGPT(
          fallbackOpenAIKey,
          finalPrompt,
          "gpt-image-2",
          normalized.images,
          normalized.quantity,
          normalized.size,
        );
        responseProvider = "gpt";
        responseModel = "gpt-image-2";
        fallbackFrom = "google";
      }
    } else {
      imageBase64s = await generateWithGPT(
        providerKeys[0],
        finalPrompt,
        normalized.model,
        normalized.images,
        normalized.quantity,
        normalized.size,
      );
    }

    return json({
      imageBase64: imageBase64s[0],
      imageBase64s,
      prompt: normalized.prompt,
      provider: responseProvider,
      model: responseModel,
      fallbackFrom,
      category: normalized.category.id,
      size: normalized.size.id,
      quantity: imageBase64s.length,
      costCredits: normalized.costCredits,
      creditsRemaining: spent.credits,
    }, 200);
  } catch (error) {
    await refundCredits(user.id, normalized.costCredits);
    return json({
      error: "provider_error",
      provider: normalized.provider,
      message: safeProviderErrorMessage(
        normalized.provider,
        error instanceof Error ? error.message : "Image generation failed",
      ),
    }, 502);
  }
});

function getProviderKeys(provider: string): string[] {
  if (provider === "google") {
    return normalizeProviderKeys([
      Deno.env.get("GEMINI_API_KEY"),
      Deno.env.get("GOOGLE_API_KEY"),
    ]);
  }
  return normalizeProviderKeys([Deno.env.get("OPENAI_API_KEY")]);
}

async function generateWithGPT(
  apiKey: string,
  finalPrompt: string,
  model: string,
  images: any[] = [],
  quantity = 1,
  size: any = {},
): Promise<string[]> {
  if (images.length > 0) {
    const results = [];
    for (let index = 0; index < quantity; index += 1) {
      results.push(await editWithGPT(apiKey, finalPrompt, model, images, size));
    }
    return results;
  }

  const response = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: model || Deno.env.get("OPENAI_IMAGE_MODEL") || "gpt-image-2",
      prompt: finalPrompt,
      size: size.openaiSize || "1024x1024",
      quality: "low",
      n: quantity,
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      payload?.error?.message || `OpenAI error ${response.status}`,
    );
  }

  const imageBase64s = (payload?.data || []).map((item: any) => item?.b64_json)
    .filter(Boolean);
  if (imageBase64s.length === 0) {
    throw new Error("OpenAI returned no image");
  }
  return imageBase64s;
}

async function editWithGPT(
  apiKey: string,
  finalPrompt: string,
  model: string,
  images: any[],
  size: any,
): Promise<string> {
  const form = new FormData();
  form.append(
    "model",
    model || Deno.env.get("OPENAI_IMAGE_MODEL") || "gpt-image-2",
  );
  form.append("prompt", finalPrompt);
  form.append("size", size.openaiSize || "1024x1024");
  form.append("quality", "low");

  images.slice(0, 6).forEach((image, index) => {
    const bytes = decodeBase64(image.data);
    const mimeType = image.mimeType || "image/jpeg";
    const ext = mimeType.includes("png")
      ? "png"
      : mimeType.includes("webp")
      ? "webp"
      : "jpg";
    form.append(
      "image[]",
      new Blob([bytes.buffer as ArrayBuffer], { type: mimeType }),
      `reference-${index + 1}.${ext}`,
    );
  });

  const response = await fetch(OPENAI_EDIT_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
    },
    body: form,
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      payload?.error?.message || `OpenAI edit error ${response.status}`,
    );
  }

  const imageBase64 = payload?.data?.[0]?.b64_json;
  if (!imageBase64) {
    throw new Error("OpenAI returned no edited image");
  }
  return imageBase64;
}

async function generateWithGoogle(
  apiKeys: string[],
  finalPrompt: string,
  requestedModel: string,
  images: any[] = [],
  quantity = 1,
  size: any = {},
): Promise<string[]> {
  const results = [];
  for (let index = 0; index < quantity; index += 1) {
    results.push(
      await generateOneWithGoogle(
        apiKeys,
        finalPrompt,
        requestedModel,
        images,
        size,
      ),
    );
  }
  return results;
}

async function generateOneWithGoogle(
  apiKeys: string[],
  finalPrompt: string,
  requestedModel: string,
  images: any[] = [],
  size: any = {},
): Promise<string> {
  const model = requestedModel || Deno.env.get("GOOGLE_IMAGE_MODEL") ||
    GOOGLE_MODEL;
  const input = [
    { type: "text", text: finalPrompt },
    ...images.slice(0, 6).map((image) => ({
      type: "image",
      mime_type: image.mimeType || "image/jpeg",
      data: image.data,
    })),
  ];
  const bodyWithSize = {
    model,
    input,
    response_format: googleResponseFormat(size, model),
  };
  const bodyWithoutSize = {
    model,
    input,
    response_format: { type: "image", mime_type: "image/jpeg" },
  };
  let response: Response | undefined;
  let payload: any = {};
  for (let keyIndex = 0; keyIndex < apiKeys.length; keyIndex += 1) {
    const apiKey = apiKeys[keyIndex];
    response = await postGoogleImageRequest(apiKey, bodyWithSize);
    payload = await response.json().catch(() => ({}));
    if (!response.ok && shouldRetryGoogleWithoutImageConfig(payload)) {
      response = await postGoogleImageRequest(apiKey, bodyWithoutSize);
      payload = await response.json().catch(() => ({}));
    }
    if (response.ok) break;
    if (
      keyIndex < apiKeys.length - 1 &&
      shouldRetryGoogleWithNextKey(payload, response.status)
    ) {
      continue;
    }
    const providerError = Object.assign(
      new Error(extractGoogleErrorMessage(payload, response.status)),
      { status: response.status },
    );
    throw providerError;
  }

  if (!response?.ok) {
    const providerError = Object.assign(
      new Error(extractGoogleErrorMessage(payload, response?.status || 502)),
      { status: response?.status || 502 },
    );
    throw providerError;
  }

  const imageBase64 = extractGoogleImageData(payload);
  if (!imageBase64) {
    const providerError = Object.assign(new Error("Google returned no image"), {
      status: 422,
    });
    throw providerError;
  }
  return imageBase64;
}

function postGoogleImageRequest(
  apiKey: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return fetch(GOOGLE_INTERACTIONS_URL, {
    method: "POST",
    headers: {
      "x-goog-api-key": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function shouldRetryGoogleWithoutImageConfig(payload: any): boolean {
  const message = String(payload?.error?.message || "").toLowerCase();
  return message.includes("imageconfig") ||
    message.includes("image_config") ||
    message.includes("imagesize") ||
    message.includes("image_size") ||
    message.includes("unknown field") ||
    message.includes("unsupported");
}

function decodeBase64(data: string): Uint8Array {
  const binary = atob(data);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function verifyUser(
  authorization: string,
): Promise<{ id: string } | null> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) return null;

  const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      "Authorization": authorization,
      "apikey": anonKey,
    },
  });
  if (!res.ok) return null;
  return await res.json().catch(() => null);
}

async function spendCredits(
  userId: string,
  amount: number,
): Promise<
  { ok: true; credits: number } | {
    ok: false;
    status: number;
    error: string;
    credits?: number;
  }
> {
  const rows = await callCreditRpc("spend_generation_credits", userId, amount);
  if (rows === null) {
    return { ok: false, status: 500, error: "credit_service_unavailable" };
  }
  if (!rows[0]) {
    const credits = await readCredits(userId);
    return {
      ok: false,
      status: 402,
      error: "insufficient_credits",
      credits: credits ?? 0,
    };
  }
  return { ok: true, credits: Number(rows[0].credits ?? 0) };
}

async function refundCredits(userId: string, amount: number): Promise<void> {
  await callCreditRpc("refund_generation_credits", userId, amount);
}

async function callCreditRpc(
  name: string,
  userId: string,
  amount: number,
): Promise<any[] | null> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return null;

  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_user_id: userId,
      p_amount: amount,
    }),
  });
  if (!response.ok) return null;
  return await response.json().catch(() => null);
}

async function readCredits(userId: string): Promise<number | null> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return null;

  const url = new URL(`${supabaseUrl}/rest/v1/profiles`);
  url.searchParams.set("id", `eq.${userId}`);
  url.searchParams.set("select", "credits");
  const response = await fetch(url, {
    headers: {
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
    },
  });
  if (!response.ok) return null;
  const rows = await response.json().catch(() => []);
  return Number(rows?.[0]?.credits ?? 0);
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
