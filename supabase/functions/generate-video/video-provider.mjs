import { FalKlingProvider } from "./fal-provider.mjs";
import { GoogleGeminiVideoProvider } from "./google-provider.mjs";
import { OpenAIVideoProvider } from "./openai-provider.mjs";

export function selectVideoProvider({
  model = "auto",
  falKey,
  googleKey,
  openAIKey,
  fetchImpl = fetch,
}) {
  if (model === "seedance-1.5-pro") {
    if (!String(falKey || "").trim()) {
      throw new Error("provider_not_configured");
    }
    return {
      name: "fal",
      requestedModel: model,
      adapter: new FalKlingProvider({
        apiKey: String(falKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (model !== "auto") {
    throw new Error("unsupported_model");
  }
  if (String(falKey || "").trim()) {
    return {
      name: "fal",
      requestedModel: model,
      adapter: new FalKlingProvider({
        apiKey: String(falKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (String(googleKey || "").trim()) {
    return {
      name: "google",
      requestedModel: model,
      adapter: new GoogleGeminiVideoProvider({
        apiKey: String(googleKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (String(openAIKey || "").trim()) {
    return {
      name: "openai",
      requestedModel: model,
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
  { model = "auto", falKey, googleKey, openAIKey, fetchImpl = fetch },
) {
  if (!["auto", "seedance-1.5-pro"].includes(model)) {
    throw new Error("unsupported_model");
  }
  if (model === "seedance-1.5-pro" && providerName !== "fal") {
    throw new Error("provider_not_configured");
  }
  if (providerName === "fal" && String(falKey || "").trim()) {
    return {
      name: "fal",
      requestedModel: model,
      adapter: new FalKlingProvider({
        apiKey: String(falKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (providerName === "google" && String(googleKey || "").trim()) {
    return {
      name: "google",
      requestedModel: model,
      adapter: new GoogleGeminiVideoProvider({
        apiKey: String(googleKey).trim(),
        fetchImpl,
      }),
    };
  }
  if (providerName === "openai" && String(openAIKey || "").trim()) {
    return {
      name: "openai",
      requestedModel: model,
      adapter: new OpenAIVideoProvider({
        apiKey: String(openAIKey).trim(),
        fetchImpl,
      }),
    };
  }
  throw new Error("provider_not_configured");
}
