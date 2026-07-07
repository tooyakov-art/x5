export const IMAGE_CREDIT_COST = 60;
export const MIN_IMAGE_QUANTITY = 1;
export const MAX_IMAGE_QUANTITY = 4;

export const generationModels = [
  { id: "gpt-image-2", provider: "gpt", title: "GPT Image 2" },
  { id: "gemini-3.1-flash-image", provider: "google", title: "Nano Banana 2" },
  { id: "gemini-3.1-flash-lite-image", provider: "google", title: "Nano Banana 2 Lite" },
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
    promptGuide: "Design a premium logo concept with clear shape, strong silhouette, and no tiny unreadable text.",
  },
  {
    id: "square_1_1",
    title: "1:1 Creative",
    promptGuide: "Create a square 1:1 advertising creative with a clear product or offer, strong hierarchy, and readable mobile composition.",
  },
  {
    id: "story",
    title: "Story",
    promptGuide: "Create a vertical Instagram story creative with strong central composition and space for overlay text.",
  },
  {
    id: "target_ad",
    title: "Target Ad",
    promptGuide: "Create a performance ad creative for Instagram or TikTok with a clear hook, benefit, and call-to-action area.",
  },
  {
    id: "youtube_cover",
    title: "YouTube Cover",
    promptGuide: "Create a clickable YouTube thumbnail with bold readable headline space, strong subject focus, and high contrast.",
  },
  {
    id: "post",
    title: "Post",
    promptGuide: "Create a square Instagram post creative with premium commercial lighting and a clear focal point.",
  },
  {
    id: "insta_pack",
    title: "Instagram Pack",
    promptGuide: "Create a cohesive Instagram packaging-style visual system: post cover, story mood, and brand texture in one square preview.",
  },
  {
    id: "product",
    title: "Product",
    promptGuide: "Create a product advertising visual with clean studio lighting, premium reflections, and sharp product focus.",
  },
  {
    id: "packaging",
    title: "Packaging",
    promptGuide: "Create a premium packaging concept with realistic material, label hierarchy, and shelf-ready presentation.",
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
    model =
      generationModels.find((item) => item.provider === requestedProvider) ||
      generationModels[0];
  }
  const provider = model.provider;
  const category =
    generationCategories.find((item) => item.id === body?.category) ||
    generationCategories[0];
  const quantity = normalizeQuantity(body?.quantity);
  const size =
    generationSizes.find((item) => item.id === body?.size) ||
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
    const data = String(item?.data || "").trim().replace(/^data:[^;]+;base64,/, "");
    const mimeType = String(item?.mimeType || item?.mime_type || "image/jpeg").trim();
    if (!data || !/^image\/(jpeg|jpg|png|webp)$/i.test(mimeType)) return [];
    return [{ data, mimeType: mimeType.toLowerCase().replace("image/jpg", "image/jpeg") }];
  });
}

export function googleResponseFormat(size = generationSizes[0], model = "") {
  const config = {
    type: "image",
    mime_type: "image/png",
    aspect_ratio: size.googleAspectRatio || "1:1",
  };
  if (model === "gemini-3.1-flash-lite-image") {
    config.image_size = "1K";
  } else if (size.googleImageSize) {
    config.image_size = size.googleImageSize;
  }
  return config;
}

export function buildFinalPrompt(prompt, category = generationCategories[0], hasImages = false) {
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
