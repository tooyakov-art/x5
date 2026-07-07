import test from "node:test";
import assert from "node:assert/strict";

import {
  IMAGE_CREDIT_COST,
  buildFinalPrompt,
  generationCategories,
  generationModels,
  generationSizes,
  googleResponseFormat,
  normalizeImages,
  normalizeGenerationRequest,
  normalizeQuantity,
} from "./economy.mjs";

test("normalizes provider, category, prompt, and fixed credit cost", () => {
  const request = normalizeGenerationRequest({
    provider: "google",
    category: "logo",
    prompt: "  premium bakery mark  ",
  });

  assert.equal(request.provider, "google");
  assert.equal(request.model, "gemini-3.1-flash-image");
  assert.equal(request.category.id, "logo");
  assert.equal(request.prompt, "premium bakery mark");
  assert.equal(request.costCredits, IMAGE_CREDIT_COST);
});

test("keeps only supported image model ids", () => {
  const gptImage2 = normalizeGenerationRequest({
    model: "gpt-image-2",
    category: "post",
    prompt: "make a premium post",
  });
  const nanoBanana2 = normalizeGenerationRequest({
    model: "gemini-3.1-flash-image",
    category: "post",
    prompt: "make a post",
  });
  const nanoBanana2Lite = normalizeGenerationRequest({
    model: "gemini-3.1-flash-lite-image",
    category: "post",
    prompt: "make a fast draft",
  });

  assert.equal(gptImage2.provider, "gpt");
  assert.equal(gptImage2.model, "gpt-image-2");
  assert.equal(nanoBanana2.provider, "google");
  assert.equal(nanoBanana2.model, "gemini-3.1-flash-image");
  assert.equal(nanoBanana2Lite.provider, "google");
  assert.equal(nanoBanana2Lite.model, "gemini-3.1-flash-lite-image");
});

test("rejects removed image models before credits are spent", () => {
  assert.throws(
    () => normalizeGenerationRequest({
      model: "gpt-image-1.5",
      category: "post",
      prompt: "old model",
    }),
    /unsupported_model/,
  );
  assert.throws(
    () => normalizeGenerationRequest({
      model: "gemini-3.1-flash-image-preview",
      category: "post",
      prompt: "old preview model",
    }),
    /unsupported_model/,
  );
});

test("falls back to GPT and custom category for unknown values", () => {
  const request = normalizeGenerationRequest({
    provider: "unknown",
    category: "unknown",
    prompt: "launch creative",
  });

  assert.equal(request.provider, "gpt");
  assert.equal(request.category.id, "custom");
});

test("normalizes quantity, size, and multiplied credit cost", () => {
  const request = normalizeGenerationRequest({
    model: "gemini-3.1-flash-image",
    category: "post",
    prompt: "make three vertical posts",
    quantity: 3,
    size: "portrait",
  });

  assert.equal(request.quantity, 3);
  assert.equal(request.costCredits, IMAGE_CREDIT_COST * 3);
  assert.equal(request.size.id, "portrait");
  assert.equal(request.size.openaiSize, "1024x1536");
  assert.equal(request.size.googleAspectRatio, "9:16");
});

test("clamps generation quantity to supported UI range", () => {
  assert.equal(normalizeQuantity(0), 1);
  assert.equal(normalizeQuantity(99), 4);
  assert.equal(normalizeQuantity("bad"), 1);
});

test("defines supported generation models", () => {
  assert.deepEqual(
    generationModels.map((model) => model.id),
    [
      "gpt-image-2",
      "gemini-3.1-flash-image",
      "gemini-3.1-flash-lite-image",
    ],
  );
});

test("downgrades Nano Banana 2 Lite image size to its supported 1K output", () => {
  const twoKSize = generationSizes.find((size) => size.id === "square_2k");

  assert.equal(
    googleResponseFormat(twoKSize, "gemini-3.1-flash-image").image_size,
    "2K",
  );
  assert.equal(
    googleResponseFormat(twoKSize, "gemini-3.1-flash-lite-image").image_size,
    "1K",
  );
});

test("defines supported generation sizes", () => {
  assert.deepEqual(
    generationSizes.map((size) => size.id),
    [
      "square",
      "portrait",
      "landscape",
      "vertical_2_3",
      "portrait_3_4",
      "portrait_4_5",
      "landscape_3_2",
      "landscape_4_3",
      "wide",
      "square_2k",
      "portrait_2k",
      "landscape_2k",
    ],
  );
});

test("rejects missing prompts", () => {
  assert.throws(
    () => normalizeGenerationRequest({ provider: "gpt", category: "post", prompt: "  " }),
    /prompt_required/,
  );
});

test("allows image edit requests without a prompt", () => {
  const request = normalizeGenerationRequest({
    model: "gemini-3.1-flash-image",
    category: "custom",
    prompt: "",
    images: [{ mimeType: "image/png", data: "abc123" }],
  });

  assert.equal(request.prompt, "Improve the provided image.");
  assert.equal(request.images.length, 1);
});

test("builds category-specific generation prompt", () => {
  const logo = generationCategories.find((category) => category.id === "logo");
  const finalPrompt = buildFinalPrompt("minimal coffee brand", logo);

  assert.match(finalPrompt, /logo/i);
  assert.match(finalPrompt, /minimal coffee brand/);
});

test("builds conservative edit prompt when images are attached", () => {
  const finalPrompt = buildFinalPrompt("improve image", generationCategories[0], true);

  assert.match(finalPrompt, /Preserve the original subject/i);
  assert.match(finalPrompt, /Do not invent unrelated objects/i);
  assert.match(finalPrompt, /text readability/i);
});

test("normalizes image references for edit requests", () => {
  const images = normalizeImages([
    { mimeType: "image/jpg", data: "data:image/jpeg;base64,abc123" },
    { mimeType: "text/plain", data: "bad" },
  ]);

  assert.deepEqual(images, [
    { mimeType: "image/jpeg", data: "abc123" },
  ]);
});
