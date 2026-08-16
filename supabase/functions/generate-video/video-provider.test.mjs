import assert from "node:assert/strict";
import test from "node:test";

import { selectVideoProvider } from "./video-provider.mjs";

test("an explicit Seedance request requires fal even when fallback keys exist", () => {
  assert.throws(
    () =>
      selectVideoProvider({
        model: "seedance-1.5-pro",
        falKey: "",
        googleKey: "google-server-key",
        openAIKey: "openai-server-key",
      }),
    /provider_not_configured/,
  );

  const selected = selectVideoProvider({
    model: "seedance-1.5-pro",
    falKey: "fal-server-key",
    googleKey: "google-server-key",
    openAIKey: "openai-server-key",
  });
  assert.equal(selected.name, "fal");
  assert.equal(selected.requestedModel, "seedance-1.5-pro");
});

test("automatic model selection keeps the existing provider order", () => {
  const google = selectVideoProvider({
    model: "auto",
    falKey: "",
    googleKey: "google-server-key",
    openAIKey: "openai-server-key",
  });
  assert.equal(google.name, "google");
  assert.equal(google.requestedModel, "auto");

  const openAI = selectVideoProvider({
    model: "auto",
    falKey: "",
    googleKey: "",
    openAIKey: "openai-server-key",
  });
  assert.equal(openAI.name, "openai");
  assert.equal(openAI.requestedModel, "auto");
});
