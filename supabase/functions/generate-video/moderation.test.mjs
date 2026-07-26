import assert from "node:assert/strict";
import test from "node:test";

import { createOpenAIVideoModerator } from "./moderation.mjs";

const normalized = {
  prompt: "A friendly mango dances in a clean studio",
  startImage: {
    mimeType: "image/jpeg",
    dataBase64: "/9j/2Q==",
  },
};

test("sends text and the optional image to omni moderation", async () => {
  const requests = [];
  const moderate = createOpenAIVideoModerator({
    apiKey: "openai-server-key",
    fetchImpl: async (url, init) => {
      requests.push({ url: String(url), init });
      return Response.json({ results: [{ flagged: false }] });
    },
  });

  assert.deepEqual(await moderate(normalized), { allowed: true });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, "https://api.openai.com/v1/moderations");
  assert.equal(
    requests[0].init.headers.Authorization,
    "Bearer openai-server-key",
  );
  const body = JSON.parse(requests[0].init.body);
  assert.equal(body.model, "omni-moderation-latest");
  assert.deepEqual(body.input, [
    { type: "text", text: normalized.prompt },
    {
      type: "image_url",
      image_url: {
        url: "data:image/jpeg;base64,/9j/2Q==",
      },
    },
  ]);
});

test("returns rejected only for a valid flagged response", async () => {
  const moderate = createOpenAIVideoModerator({
    apiKey: "openai-server-key",
    fetchImpl: async () => Response.json({ results: [{ flagged: true }] }),
  });

  assert.deepEqual(
    await moderate({ prompt: "unsafe", startImage: null }),
    { allowed: false },
  );
});

test("fails closed for missing config, HTTP errors, and malformed responses", async () => {
  assert.throws(
    () => createOpenAIVideoModerator({ apiKey: "" }),
    /video_moderation_not_configured/,
  );

  for (
    const response of [
      new Response("provider details", { status: 429 }),
      Response.json({ results: [] }),
      Response.json({ results: [{ categories: {} }] }),
    ]
  ) {
    const moderate = createOpenAIVideoModerator({
      apiKey: "openai-server-key",
      fetchImpl: async () => response,
    });
    await assert.rejects(
      () => moderate({ prompt: "hello", startImage: null }),
      /video_moderation_unavailable/,
    );
  }
});
