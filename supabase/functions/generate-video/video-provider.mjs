import { FalKlingProvider } from "./fal-provider.mjs";
import { GoogleGeminiVideoProvider } from "./google-provider.mjs";
import { OpenAIVideoProvider } from "./openai-provider.mjs";

export function selectVideoProvider({
  falKey,
  googleKey,
  openAIKey,
  fetchImpl = fetch,
}) {
  if (String(falKey || "").trim()) {
    return {
      name: "fal",
      adapter: new FalKlingProvider({
        apiKey: String(falKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (String(googleKey || "").trim()) {
    return {
      name: "google",
      adapter: new GoogleGeminiVideoProvider({
        apiKey: String(googleKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (String(openAIKey || "").trim()) {
    return {
      name: "openai",
      adapter: new OpenAIVideoProvider({
        apiKey: String(openAIKey).trim(),
        fetchImpl,
      }),
    };
  }
  throw new Error("provider_not_configured");
}

export function selectVideoProviderByName(
  providerName,
  { falKey, googleKey, openAIKey, fetchImpl = fetch },
) {
  if (providerName === "fal" && String(falKey || "").trim()) {
    return {
      name: "fal",
      adapter: new FalKlingProvider({
        apiKey: String(falKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (providerName === "google" && String(googleKey || "").trim()) {
    return {
      name: "google",
      adapter: new GoogleGeminiVideoProvider({
        apiKey: String(googleKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (providerName === "openai" && String(openAIKey || "").trim()) {
    return {
      name: "openai",
      adapter: new OpenAIVideoProvider({
        apiKey: String(openAIKey).trim(),
        fetchImpl,
      }),
    };
  }
  throw new Error("provider_not_configured");
}
