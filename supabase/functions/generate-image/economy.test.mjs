import test from "node:test";
import assert from "node:assert/strict";

import {
  IMAGE_CREDIT_COST,
  buildFinalPrompt,
  generationCategories,
  normalizeImages,
  normalizeGenerationRequest,
} from "./economy.mjs";

test("normalizes provider, category, prompt, and fixed credit cost", () => {
  const request = normalizeGenerationRequest({
    provider: "google",
    category: "logo",
    prompt: "  premium bakery mark  ",
  });

  assert.equal(request.provider, "google");
  assert.equal(request.category.id, "logo");
  assert.equal(request.prompt, "premium bakery mark");
  assert.equal(request.costCredits, IMAGE_CREDIT_COST);
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

test("rejects missing prompts", () => {
  assert.throws(
    () => normalizeGenerationRequest({ provider: "gpt", category: "post", prompt: "  " }),
    /prompt_required/,
  );
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
