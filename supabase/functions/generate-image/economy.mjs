export const IMAGE_CREDIT_COST = 10;

export const generationModels = [
  { id: "gpt-image-2", provider: "gpt", title: "GPT Image 2" },
  { id: "gpt-image-1.5", provider: "gpt", title: "GPT Image 1.5" },
  { id: "gpt-image-1-mini", provider: "gpt", title: "GPT Image Mini" },
  { id: "gpt-image-1", provider: "gpt", title: "GPT Image" },
  { id: "gemini-3-pro-image-preview", provider: "google", title: "Nano Banana Pro" },
  { id: "gemini-3.1-flash-image-preview", provider: "google", title: "Nano Banana 2" },
  { id: "gemini-2.5-flash-image", provider: "google", title: "Nano Banana" },
];

export const generationProviders = [
  { id: "gpt", title: "GPT" },
  { id: "google", title: "Google" },
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
    id: "story",
    title: "Story",
    promptGuide: "Create a vertical Instagram story creative with strong central composition and space for overlay text.",
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
  let prompt = String(body?.prompt || "").trim();
  if (prompt.length < 3) {
    throw new GenerationRequestError("prompt_required", 400);
  }
  if (prompt.length > 900) {
    prompt = prompt.slice(0, 900);
  }

  const model = generationModels.find((item) => item.id === body?.model) || generationModels[0];
  const provider = model.provider;
  const category =
    generationCategories.find((item) => item.id === body?.category) ||
    generationCategories[0];

  return {
    prompt,
    provider,
    model: model.id,
    category,
    costCredits: IMAGE_CREDIT_COST,
  };
}

export function buildFinalPrompt(prompt, category = generationCategories[0]) {
  return [
    prompt,
    category.promptGuide,
    "No explicit sexual content, hate, gore, real-person impersonation, or misleading medical/financial claims.",
    "Premium commercial composition, clean lighting, high detail, ready for social media or ads.",
  ].join("\n");
}
