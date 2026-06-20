// Supabase Edge Function: generate-image
//
// Required env:
//   OPENAI_API_KEY
//   GOOGLE_API_KEY or GEMINI_API_KEY
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY

import {
  GenerationRequestError,
  buildFinalPrompt,
  normalizeGenerationRequest,
} from "./economy.mjs";

const OPENAI_URL = "https://api.openai.com/v1/images/generations";
const OPENAI_EDIT_URL = "https://api.openai.com/v1/images/edits";
const OPENAI_MODEL = "gpt-image-1";
const GOOGLE_MODEL = "gemini-3.1-flash-image-preview";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  const requestId = crypto.randomUUID();
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

  let generationAttempt = {
    provider: normalized.provider,
    model: normalized.model,
  };
  let providerKey = getProviderKey(generationAttempt.provider);
  if (!providerKey) {
    const fallback = fallbackAttempt(generationAttempt.provider);
    const fallbackKey = fallback ? getProviderKey(fallback.provider) : undefined;
    if (fallback && fallbackKey) {
      await logDiagnostic("image_generation_provider_fallback", {
        request_id: requestId,
        user_id: user.id,
        reason: "primary_key_missing",
        from_provider: generationAttempt.provider,
        from_model: generationAttempt.model,
        to_provider: fallback.provider,
        to_model: fallback.model,
      });
      generationAttempt = fallback;
      providerKey = fallbackKey;
    }
  }
  if (!providerKey) {
    await logDiagnostic("image_generation_provider_not_configured", {
      request_id: requestId,
      user_id: user.id,
      provider: normalized.provider,
      model: normalized.model,
    });
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
    await logDiagnostic("image_generation_credit_failed", {
      request_id: requestId,
      user_id: user.id,
      provider: normalized.provider,
      model: normalized.model,
      error: spent.error,
      credits_required: normalized.costCredits,
      credits_remaining: spent.credits ?? 0,
    });
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
    const imageBase64s = await generateWithFallback(
      requestId,
      user.id,
      providerKey,
      finalPrompt,
      generationAttempt,
      normalized,
    );

    return json({
      imageBase64: imageBase64s[0],
      imageBase64s,
      prompt: normalized.prompt,
      provider: generationAttempt.provider,
      model: generationAttempt.model,
      category: normalized.category.id,
      size: normalized.size.id,
      quantity: imageBase64s.length,
      costCredits: normalized.costCredits,
      creditsRemaining: spent.credits,
    }, 200);
  } catch (error) {
    await refundCredits(user.id, normalized.costCredits);
    await logDiagnostic("image_generation_failed", {
      request_id: requestId,
      user_id: user.id,
      provider: normalized.provider,
      model: normalized.model,
      message: errorMessage(error),
    });
    return json({
      error: "provider_error",
      provider: normalized.provider,
      message: errorMessage(error),
    }, 502);
  }
});

function getProviderKey(provider: string): string | undefined {
  if (provider === "google") {
    return Deno.env.get("GOOGLE_API_KEY") || Deno.env.get("GEMINI_API_KEY") || undefined;
  }
  return Deno.env.get("OPENAI_API_KEY") || undefined;
}

function fallbackAttempt(provider: string): { provider: string; model: string } | null {
  if (provider === "google") {
    return { provider: "gpt", model: Deno.env.get("OPENAI_IMAGE_MODEL") || OPENAI_MODEL };
  }
  return { provider: "google", model: Deno.env.get("GOOGLE_IMAGE_MODEL") || "gemini-2.5-flash-image" };
}

async function generateWithFallback(
  requestId: string,
  userId: string,
  providerKey: string,
  finalPrompt: string,
  generationAttempt: { provider: string; model: string },
  normalized: any,
): Promise<string[]> {
  try {
    const imageBase64s = await generateWithProvider(
      providerKey,
      finalPrompt,
      generationAttempt.provider,
      generationAttempt.model,
      normalized.images,
      normalized.quantity,
      normalized.size,
    );
    await logDiagnostic("image_generation_success", {
      request_id: requestId,
      user_id: userId,
      provider: generationAttempt.provider,
      model: generationAttempt.model,
      quantity: imageBase64s.length,
    });
    return imageBase64s;
  } catch (primaryError) {
    await logDiagnostic("image_generation_provider_error", {
      request_id: requestId,
      user_id: userId,
      stage: "primary",
      provider: generationAttempt.provider,
      model: generationAttempt.model,
      message: errorMessage(primaryError),
    });

    const fallback = fallbackAttempt(generationAttempt.provider);
    const fallbackKey = fallback ? getProviderKey(fallback.provider) : undefined;
    if (!fallback || !fallbackKey) {
      throw primaryError;
    }

    try {
      const imageBase64s = await generateWithProvider(
        fallbackKey,
        finalPrompt,
        fallback.provider,
        fallback.model,
        normalized.images,
        normalized.quantity,
        normalized.size,
      );
      generationAttempt.provider = fallback.provider;
      generationAttempt.model = fallback.model;
      await logDiagnostic("image_generation_provider_fallback", {
        request_id: requestId,
        user_id: userId,
        reason: "primary_failed",
        from_provider: normalized.provider,
        from_model: normalized.model,
        to_provider: fallback.provider,
        to_model: fallback.model,
        quantity: imageBase64s.length,
      });
      return imageBase64s;
    } catch (fallbackError) {
      await logDiagnostic("image_generation_provider_error", {
        request_id: requestId,
        user_id: userId,
        stage: "fallback",
        provider: fallback.provider,
        model: fallback.model,
        message: errorMessage(fallbackError),
      });
      throw fallbackError;
    }
  }
}

function generateWithProvider(
  apiKey: string,
  finalPrompt: string,
  provider: string,
  model: string,
  images: any[] = [],
  quantity = 1,
  size: any = {},
): Promise<string[]> {
  if (provider === "google") {
    return generateWithGoogle(apiKey, finalPrompt, model, images, quantity, size);
  }
  return generateWithGPT(apiKey, finalPrompt, model, images, quantity, size);
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
      model: model || Deno.env.get("OPENAI_IMAGE_MODEL") || OPENAI_MODEL,
      prompt: finalPrompt,
      size: size.openaiSize || "1024x1024",
      quality: "low",
      n: quantity,
    }),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload?.error?.message || `OpenAI error ${response.status}`);
  }

  const imageBase64s = (payload?.data || []).map((item: any) => item?.b64_json).filter(Boolean);
  if (imageBase64s.length === 0) {
    throw new Error("OpenAI returned no image");
  }
  return imageBase64s;
}

async function editWithGPT(apiKey: string, finalPrompt: string, model: string, images: any[], size: any): Promise<string> {
  const form = new FormData();
  form.append("model", model || Deno.env.get("OPENAI_IMAGE_MODEL") || OPENAI_MODEL);
  form.append("prompt", finalPrompt);
  form.append("size", size.openaiSize || "1024x1024");
  form.append("quality", "low");

  images.slice(0, 6).forEach((image, index) => {
    const bytes = decodeBase64(image.data);
    const mimeType = image.mimeType || "image/jpeg";
    const ext = mimeType.includes("png") ? "png" : mimeType.includes("webp") ? "webp" : "jpg";
    form.append("image", new Blob([bytes], { type: mimeType }), `reference-${index + 1}.${ext}`);
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
    throw new Error(payload?.error?.message || `OpenAI edit error ${response.status}`);
  }

  const imageBase64 = payload?.data?.[0]?.b64_json;
  if (!imageBase64) {
    throw new Error("OpenAI returned no edited image");
  }
  return imageBase64;
}

async function generateWithGoogle(
  apiKey: string,
  finalPrompt: string,
  requestedModel: string,
  images: any[] = [],
  quantity = 1,
  size: any = {},
): Promise<string[]> {
  const results = [];
  for (let index = 0; index < quantity; index += 1) {
    results.push(await generateOneWithGoogle(apiKey, finalPrompt, requestedModel, images, size));
  }
  return results;
}

async function generateOneWithGoogle(
  apiKey: string,
  finalPrompt: string,
  requestedModel: string,
  images: any[] = [],
  size: any = {},
): Promise<string> {
  const model = requestedModel || Deno.env.get("GOOGLE_IMAGE_MODEL") || GOOGLE_MODEL;
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const requestParts = [
    { text: finalPrompt },
    ...images.slice(0, 6).map((image) => ({
      inline_data: {
        mime_type: image.mimeType || "image/jpeg",
        data: image.data,
      },
    })),
  ];
  const bodyWithSize = {
    contents: [{ parts: requestParts }],
    generationConfig: {
      responseModalities: ["TEXT", "IMAGE"],
      imageConfig: googleImageConfig(size),
    },
  };
  const bodyWithoutSize = {
    contents: [{ parts: requestParts }],
    generationConfig: {
      responseModalities: ["TEXT", "IMAGE"],
    },
  };
  let response = await postGoogleImageRequest(url, apiKey, bodyWithSize);
  let payload = await response.json().catch(() => ({}));
  if (!response.ok && shouldRetryGoogleWithoutImageConfig(payload)) {
    response = await postGoogleImageRequest(url, apiKey, bodyWithoutSize);
    payload = await response.json().catch(() => ({}));
  }

  if (!response.ok) {
    throw new Error(payload?.error?.message || `Google error ${response.status}`);
  }

  const responseParts = payload?.candidates?.[0]?.content?.parts || [];
  const imagePart = responseParts.find((part: any) => part?.inlineData?.data || part?.inline_data?.data);
  const imageBase64 = imagePart?.inlineData?.data || imagePart?.inline_data?.data;
  if (!imageBase64) {
    throw new Error("Google returned no image");
  }
  return imageBase64;
}

function postGoogleImageRequest(url: string, apiKey: string, body: Record<string, unknown>): Promise<Response> {
  return fetch(url, {
    method: "POST",
    headers: {
      "x-goog-api-key": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function googleImageConfig(size: any): Record<string, string> {
  const config: Record<string, string> = {
    aspectRatio: size.googleAspectRatio || "1:1",
  };
  if (size.googleImageSize) {
    config.imageSize = size.googleImageSize;
  }
  return config;
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

async function verifyUser(authorization: string): Promise<{ id: string } | null> {
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
): Promise<{ ok: true; credits: number } | { ok: false; status: number; error: string; credits?: number }> {
  const rows = await callCreditRpc("spend_generation_credits", userId, amount);
  if (rows === null) {
    return { ok: false, status: 500, error: "credit_service_unavailable" };
  }
  if (!rows[0]) {
    const credits = await readCredits(userId);
    return { ok: false, status: 402, error: "insufficient_credits", credits: credits ?? 0 };
  }
  return { ok: true, credits: Number(rows[0].credits ?? 0) };
}

async function refundCredits(userId: string, amount: number): Promise<void> {
  await callCreditRpc("refund_generation_credits", userId, amount);
}

async function callCreditRpc(name: string, userId: string, amount: number): Promise<any[] | null> {
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

async function logDiagnostic(event: string, extra: Record<string, unknown> = {}): Promise<void> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return;

  const summary = Object.entries(extra)
    .map(([key, value]) => `${key}=${String(value).slice(0, 220)}`)
    .sort()
    .join("; ")
    .slice(0, 3000);

  await fetch(`${supabaseUrl}/rest/v1/app_diagnostics`, {
    method: "POST",
    headers: {
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      "Prefer": "return=minimal",
    },
    body: JSON.stringify({
      build_number: "edge-generate-image",
      app_version: "edge",
      device_model: "supabase-edge",
      locale: "server",
      event,
      summary,
      ts: new Date().toISOString(),
    }),
  }).catch(() => {});
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return sanitizeProviderMessage(String(error.message || "Image generation failed")).slice(0, 500);
  }
  return "Image generation failed";
}

function sanitizeProviderMessage(message: string): string {
  const lower = message.toLowerCase();
  if (lower.includes("api_key") && lower.includes("suspended")) {
    return "Google image provider is suspended. Use GPT Image while the Google key is replaced.";
  }
  return message.replace(/api_key:[A-Za-z0-9_-]+/g, "api_key:<redacted>");
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
