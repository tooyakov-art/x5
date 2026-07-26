const OPENAI_MODERATIONS_URL = "https://api.openai.com/v1/moderations";
const MODERATION_MODEL = "omni-moderation-latest";

export function createOpenAIVideoModerator({
  apiKey,
  fetchImpl = fetch,
  timeoutMs = 20_000,
}) {
  const normalizedKey = String(apiKey || "").trim();
  if (!normalizedKey) throw new Error("video_moderation_not_configured");

  return async function moderateVideoRequest(normalized) {
    const input = [{
      type: "text",
      text: String(normalized?.prompt || ""),
    }];
    if (normalized?.startImage) {
      input.push({
        type: "image_url",
        image_url: {
          url:
            `data:${normalized.startImage.mimeType};base64,${normalized.startImage.dataBase64}`,
        },
      });
    }

    let response;
    try {
      response = await fetchImpl(OPENAI_MODERATIONS_URL, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${normalizedKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: MODERATION_MODEL,
          input,
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      throw new Error("video_moderation_unavailable");
    }

    const payload = await response.json().catch(() => null);
    const flagged = payload?.results?.[0]?.flagged;
    if (!response.ok || typeof flagged !== "boolean") {
      throw new Error("video_moderation_unavailable");
    }
    return { allowed: !flagged };
  };
}
