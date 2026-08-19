export const CUSTOMER_PRICE_MULTIPLIER = 2;
export const IMAGE_PROVIDER_COST_CREDITS = 30;
export const IMAGE_CREDIT_COST =
  IMAGE_PROVIDER_COST_CREDITS * CUSTOMER_PRICE_MULTIPLIER;
export const MIN_IMAGE_QUANTITY = 1;
export const MAX_IMAGE_QUANTITY = 4;

export const generationModels = [
  { id: "gpt-image-2", provider: "gpt", title: "GPT Image 2" },
  { id: "gemini-3.1-flash-image", provider: "google", title: "Nano Banana 2" },
  {
    id: "gemini-3.1-flash-lite-image",
    provider: "google",
    title: "Nano Banana 2 Lite",
  },
];

export const generationProviders = [
  { id: "gpt", title: "GPT" },
  { id: "google", title: "Google" },
];

export const generationSizes = [
  {
    id: "square",
    title: "1:1",
    openaiSize: "1024x1024",
    googleAspectRatio: "1:1",
  },
  {
    id: "portrait",
    title: "9:16",
    openaiSize: "1024x1536",
    googleAspectRatio: "9:16",
  },
  {
    id: "landscape",
    title: "16:9",
    openaiSize: "1536x1024",
    googleAspectRatio: "16:9",
  },
  {
    id: "vertical_2_3",
    title: "2:3",
    openaiSize: "1024x1536",
    googleAspectRatio: "2:3",
  },
  {
    id: "portrait_3_4",
    title: "3:4",
    openaiSize: "1024x1536",
    googleAspectRatio: "3:4",
  },
  {
    id: "portrait_4_5",
    title: "4:5",
    openaiSize: "1024x1536",
    googleAspectRatio: "4:5",
  },
  {
    id: "landscape_3_2",
    title: "3:2",
    openaiSize: "1536x1024",
    googleAspectRatio: "3:2",
  },
  {
    id: "landscape_4_3",
    title: "4:3",
    openaiSize: "1536x1024",
    googleAspectRatio: "4:3",
  },
  {
    id: "wide",
    title: "21:9",
    openaiSize: "1536x1024",
    googleAspectRatio: "21:9",
  },
  {
    id: "square_2k",
    title: "1:1 2K",
    openaiSize: "1024x1024",
    googleAspectRatio: "1:1",
    googleImageSize: "2K",
  },
  {
    id: "portrait_2k",
    title: "9:16 2K",
    openaiSize: "1024x1536",
    googleAspectRatio: "9:16",
    googleImageSize: "2K",
  },
  {
    id: "landscape_2k",
    title: "16:9 2K",
    openaiSize: "1536x1024",
    googleAspectRatio: "16:9",
    googleImageSize: "2K",
  },
];

export const generationCategories = [
  {
    id: "custom",
    title: "Custom",
    promptGuide: "Create a polished marketing-ready square image.",
  },
  {
    id: "logo",
    title: "Logo",
    promptGuide:
      "Design a premium logo concept with clear shape, strong silhouette, and no tiny unreadable text.",
  },
  {
    id: "square_1_1",
    title: "1:1 Creative",
    promptGuide:
      "Create a square 1:1 advertising creative with a clear product or offer, strong hierarchy, and readable mobile composition.",
  },
  {
    id: "story",
    title: "Story",
    promptGuide:
      "Create a vertical Instagram story creative with strong central composition and space for overlay text.",
  },
  {
    id: "target_ad",
    title: "Target Ad",
    promptGuide:
      "Create a performance ad creative for Instagram or TikTok with a clear hook, benefit, and call-to-action area.",
  },
  {
    id: "youtube_cover",
    title: "YouTube Cover",
    promptGuide:
      "Create a clickable YouTube thumbnail with bold readable headline space, strong subject focus, and high contrast.",
  },
  {
    id: "post",
    title: "Post",
    promptGuide:
      "Create a square Instagram post creative with premium commercial lighting and a clear focal point.",
  },
  {
    id: "insta_pack",
    title: "Instagram Pack",
    promptGuide:
      "Create a cohesive Instagram packaging-style visual system: post cover, story mood, and brand texture in one square preview.",
  },
  {
    id: "product",
    title: "Product",
    promptGuide:
      "Create a product advertising visual with clean studio lighting, premium reflections, and sharp product focus.",
  },
  {
    id: "packaging",
    title: "Packaging",
    promptGuide:
      "Create a premium packaging concept with realistic material, label hierarchy, and shelf-ready presentation.",
  },
];

export class GenerationRequestError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = "GenerationRequestError";
    this.code = code;
    this.status = status;
  }
}

export function normalizeGenerationRequest(body) {
  const images = normalizeImages(body?.images);
  let prompt = String(body?.prompt || "").trim();
  if (prompt.length < 3 && images.length > 0) {
    prompt = "Improve the provided image.";
  }
  if (prompt.length < 3) {
    throw new GenerationRequestError("prompt_required", 400);
  }
  if (prompt.length > 900) {
    prompt = prompt.slice(0, 900);
  }

  const requestedProvider = String(body?.provider || "").trim();
  const requestedModel = String(body?.model || "").trim();
  let model;
  if (requestedModel) {
    model = generationModels.find((item) => item.id === requestedModel);
    if (!model) {
      throw new GenerationRequestError("unsupported_model", 400);
    }
  } else {
    model = generationModels.find((item) =>
      item.provider === requestedProvider
    ) ||
      generationModels[0];
  }
  const provider = model.provider;
  const category =
    generationCategories.find((item) => item.id === body?.category) ||
    generationCategories[0];
  const quantity = normalizeQuantity(body?.quantity);
  const size = generationSizes.find((item) => item.id === body?.size) ||
    generationSizes[0];

  return {
    prompt,
    provider,
    model: model.id,
    category,
    images,
    quantity,
    size,
    costCredits: IMAGE_CREDIT_COST * quantity,
  };
}

export function normalizeQuantity(rawQuantity) {
  const parsed = Number.parseInt(String(rawQuantity ?? MIN_IMAGE_QUANTITY), 10);
  if (Number.isNaN(parsed)) return MIN_IMAGE_QUANTITY;
  return Math.min(MAX_IMAGE_QUANTITY, Math.max(MIN_IMAGE_QUANTITY, parsed));
}

export function normalizeImages(rawImages) {
  if (!Array.isArray(rawImages)) return [];

  return rawImages.slice(0, 6).flatMap((item) => {
    const data = String(item?.data || "").trim().replace(
      /^data:[^;]+;base64,/,
      "",
    );
    const mimeType = String(item?.mimeType || item?.mime_type || "image/jpeg")
      .trim();
    if (!data || !/^image\/(jpeg|jpg|png|webp)$/i.test(mimeType)) return [];
    return [{
      data,
      mimeType: mimeType.toLowerCase().replace("image/jpg", "image/jpeg"),
    }];
  });
}

export function googleResponseFormat(size = generationSizes[0], model = "") {
  const config = {
    type: "image",
    mime_type: "image/jpeg",
    aspect_ratio: size.googleAspectRatio || "1:1",
  };
  if (model === "gemini-3.1-flash-lite-image") {
    config.image_size = "1K";
  } else if (size.googleImageSize) {
    config.image_size = size.googleImageSize;
  }
  return config;
}

export function extractGoogleErrorMessage(payload, status) {
  const directMessage = payload?.error?.message;
  if (typeof directMessage === "string" && directMessage.trim()) {
    return directMessage.trim();
  }

  if (Array.isArray(payload)) {
    const nestedMessage = payload.find((item) =>
      typeof item?.error?.message === "string" && item.error.message.trim()
    )?.error?.message;
    if (nestedMessage) return nestedMessage.trim();
  }

  return `Google error ${status}`;
}

export function normalizeProviderKeys(rawKeys) {
  const seen = new Set();
  return (Array.isArray(rawKeys) ? rawKeys : []).flatMap((rawKey) => {
    const key = String(rawKey || "").trim();
    if (!key || seen.has(key)) return [];
    seen.add(key);
    return [key];
  });
}

export function shouldRetryGoogleWithNextKey(_payload, status) {
  return status === 401 ||
    status === 403 ||
    status === 404 ||
    status === 408 ||
    status === 429 ||
    status >= 500;
}

export function shouldFallbackGoogleToGPT(status) {
  return status === 400 ||
    status === 401 ||
    status === 403 ||
    status === 404 ||
    status === 408 ||
    status === 409 ||
    status === 422 ||
    status === 429 ||
    status >= 500;
}

export async function buildGenerationIdentity(
  normalized,
  body = {},
  headerIdempotencyKey = "",
) {
  const imageIdentities = await Promise.all(
    normalized.images.map(async (image) => ({
      mimeType: image.mimeType,
      sha256: await sha256Hex(image.data),
    })),
  );
  const fingerprint = await sha256Hex(JSON.stringify({
    prompt: normalized.prompt,
    provider: normalized.provider,
    model: normalized.model,
    category: normalized.category.id,
    quantity: normalized.quantity,
    size: normalized.size.id,
    images: imageIdentities,
  }));
  const explicitKey = String(
    headerIdempotencyKey ||
      body?.requestId ||
      body?.request_id ||
      body?.idempotencyKey ||
      body?.idempotency_key ||
      "",
  ).trim();

  if (!explicitKey) {
    return {
      requestKey: `legacy:${fingerprint}`,
      fingerprint,
      isLegacy: true,
    };
  }
  if (
    explicitKey.length < 8 ||
    explicitKey.length > 200 ||
    !/^[A-Za-z0-9._:-]+$/.test(explicitKey)
  ) {
    throw new GenerationRequestError("invalid_idempotency_key", 400);
  }

  return {
    requestKey: `explicit:${await sha256Hex(explicitKey)}`,
    fingerprint,
    isLegacy: false,
  };
}

export function buildGenerationResultManifest({
  provider,
  model,
  fallbackFrom,
  objects,
}) {
  return {
    version: 1,
    provider,
    model,
    ...(fallbackFrom ? { fallbackFrom } : {}),
    objects: objects.map((object) => ({
      path: object.path,
      mimeType: object.mimeType,
      sha256: object.sha256,
    })),
  };
}

export function detectGeneratedImageFormat(base64) {
  let binary;
  try {
    binary = atob(String(base64 || ""));
  } catch {
    throw new Error("unsupported_generated_image_format");
  }
  const bytes = Array.from(
    binary.slice(0, 12),
    (character) => character.charCodeAt(0),
  );
  if (
    bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47
  ) {
    return { mimeType: "image/png", extension: "png" };
  }
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return { mimeType: "image/jpeg", extension: "jpg" };
  }
  if (
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
  ) {
    return { mimeType: "image/webp", extension: "webp" };
  }
  throw new Error("unsupported_generated_image_format");
}

/**
 * @param {{
 *   normalized: ReturnType<typeof normalizeGenerationRequest>,
 *   imageBase64s: string[],
 *   imageUrls?: string[],
 *   provider: string,
 *   model: string,
 *   fallbackFrom?: string,
 *   creditsRemaining: number,
 * }} input
 */
export function buildGenerationResponse({
  normalized,
  imageBase64s,
  imageUrls = [],
  provider,
  model,
  fallbackFrom,
  creditsRemaining,
}) {
  return {
    imageBase64: imageBase64s[0],
    imageBase64s,
    ...(imageUrls[0] ? { imageUrl: imageUrls[0], imageUrls } : {}),
    prompt: normalized.prompt,
    provider,
    model,
    ...(fallbackFrom ? { fallbackFrom } : {}),
    category: normalized.category.id,
    size: normalized.size.id,
    quantity: imageBase64s.length,
    costCredits: normalized.costCredits,
    creditsRemaining,
  };
}

export async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(String(value));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function hasUsableGenerationProvider(
  requestedProvider,
  primaryKeyCount,
  fallbackKeyCount,
) {
  if (Number(primaryKeyCount) > 0) return true;
  return requestedProvider === "google" && Number(fallbackKeyCount) > 0;
}

export function extractGoogleImageData(payload) {
  const stepContent = Array.isArray(payload?.steps)
    ? payload.steps.flatMap((step) =>
      Array.isArray(step?.content) ? step.content : []
    )
    : [];
  const stepImage = stepContent.find((part) =>
    part?.type === "image" && part?.data
  );

  const candidateParts = payload?.candidates?.[0]?.content?.parts || [];
  const candidateImage = Array.isArray(candidateParts)
    ? candidateParts.find((part) =>
      part?.inlineData?.data || part?.inline_data?.data || part?.data
    )
    : undefined;
  const legacyOutput = Array.isArray(payload?.output)
    ? payload.output.find((part) =>
      part?.inlineData?.data || part?.inline_data?.data || part?.data
    )
    : undefined;

  return stepImage?.data ||
    payload?.output_image?.data ||
    legacyOutput?.inlineData?.data ||
    legacyOutput?.inline_data?.data ||
    legacyOutput?.data ||
    candidateImage?.inlineData?.data ||
    candidateImage?.inline_data?.data ||
    candidateImage?.data;
}

export function safeProviderErrorMessage(provider, _upstreamMessage = "") {
  if (provider === "google") {
    return "Генерация временно недоступна. Кредиты возвращены. Повторите позже.";
  }
  return "Генерация временно недоступна. Кредиты возвращены. Повторите позже.";
}

export function sanitizeProviderDiagnostic(rawMessage = "") {
  return String(rawMessage || "")
    .replace(/AIza[0-9A-Za-z_-]{20,}/g, "[REDACTED_GOOGLE_API_KEY]")
    .replace(/sk-[0-9A-Za-z_-]{16,}/g, "[REDACTED_OPENAI_API_KEY]")
    .replace(/Bearer\s+[0-9A-Za-z._-]{16,}/gi, "Bearer [REDACTED]")
    .slice(0, 600);
}

export function buildFinalPrompt(
  prompt,
  category = generationCategories[0],
  hasImages = false,
) {
  if (hasImages) {
    return [
      "Edit the provided image(s). Preserve the original subject, product, packaging, composition, layout, camera angle, background, and text placement unless the user explicitly asks to change them.",
      "Do not invent unrelated objects or replace the scene. If the user asks to improve/enhance/upscale, only improve clarity, sharpness, lighting, cleanup, and text readability.",
      "If the image contains text, keep the same words and make them more readable; do not create random text.",
      `User instruction: ${prompt}`,
      category.promptGuide,
      "No explicit sexual content, hate, gore, real-person impersonation, or misleading medical/financial claims.",
    ].join("\n");
  }

  return [
    prompt,
    category.promptGuide,
    "No explicit sexual content, hate, gore, real-person impersonation, or misleading medical/financial claims.",
    "Premium commercial composition, clean lighting, high detail, ready for social media or ads.",
  ].join("\n");
}
