import assert from "node:assert/strict";
import test from "node:test";

import {
  DirectVoiceProvider,
  ELEVENLABS_MODEL,
  MINIMAX_MODEL,
} from "./direct-provider.mjs";

const mp3 = Uint8Array.from([0x49, 0x44, 0x33, 4, 0, 0, 1, 2, 3]);
const input = {
  text: "Озвучь рекламный текст",
  voice: "Aria",
  stability: 0.5,
  speed: 1,
  languageCode: "ru",
};

test("uses official MiniMax HTTP MP3 endpoint first", async () => {
  let request;
  const provider = new DirectVoiceProvider({
    minimaxKey: "mini-secret",
    elevenLabsKey: "eleven-secret",
    fetchImpl: (url, options) => {
      request = { url: String(url), options };
      return Response.json({
        data: { audio: Buffer.from(mp3).toString("hex"), status: 2 },
        trace_id: "trace-12345678",
        base_resp: { status_code: 0, status_msg: "success" },
      });
    },
  });
  const result = await provider.generate({ input });
  assert.equal(request.url, "https://api.minimax.io/v1/t2a_v2");
  assert.equal(request.options.headers.Authorization, "Bearer mini-secret");
  const body = JSON.parse(request.options.body);
  assert.equal(body.model, MINIMAX_MODEL);
  assert.equal(body.language_boost, "Russian");
  assert.equal(body.audio_setting.format, "mp3");
  assert.equal(result.provider, "minimax");
  assert.equal(result.model, MINIMAX_MODEL);
  assert.deepEqual(result.audioBytes, mp3);
});

test("falls back to official ElevenLabs on a definitive MiniMax rejection", async () => {
  const calls = [];
  const provider = new DirectVoiceProvider({
    minimaxKey: "mini-secret",
    elevenLabsKey: "eleven-secret",
    fetchImpl: (url, options) => {
      calls.push({ url: String(url), options });
      if (String(url).includes("minimax.io")) {
        return Response.json(
          { base_resp: { status_code: 1004, status_msg: "rejected" } },
          { status: 400 },
        );
      }
      return new Response(mp3, {
        headers: {
          "Content-Type": "audio/mpeg",
          "request-id": "eleven-request-1234",
        },
      });
    },
  });
  const result = await provider.generate({ input });
  assert.equal(calls.length, 2);
  assert.match(
    calls[1].url,
    /^https:\/\/api\.elevenlabs\.io\/v1\/text-to-speech\//,
  );
  assert.equal(calls[1].options.headers["xi-api-key"], "eleven-secret");
  assert.equal(JSON.parse(calls[1].options.body).model_id, ELEVENLABS_MODEL);
  assert.equal(result.provider, "elevenlabs");
  assert.equal(result.model, ELEVENLABS_MODEL);
});

test("never double-submits to fallback after an ambiguous MiniMax transport", async () => {
  let calls = 0;
  const provider = new DirectVoiceProvider({
    minimaxKey: "mini-secret",
    elevenLabsKey: "eleven-secret",
    fetchImpl: () => {
      calls += 1;
      throw new Error("timeout");
    },
  });
  await assert.rejects(
    provider.generate({ input }),
    (error) => error.submissionAmbiguous === true,
  );
  assert.equal(calls, 1);
});
