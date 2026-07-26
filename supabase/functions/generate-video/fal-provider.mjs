const FAL_QUEUE_ROOT = "https://queue.fal.run";
const TEXT_MODEL = "fal-ai/kling-video/v3/standard/text-to-video";
const IMAGE_MODEL = "fal-ai/kling-video/v3/standard/image-to-video";
const NEGATIVE_PROMPT =
  "blur, distort, low quality, explicit sexual content, gore";
const SAFE_FALLBACK_HTTP_STATUSES = new Set([429]);

export class FalProviderError extends Error {
  constructor(code, options = {}) {
    super(code);
    this.name = "FalProviderError";
    this.code = code;
    const normalized = typeof options === "boolean"
      ? { retryable: options }
      : options;
    this.retryable = normalized.retryable !== false;
    this.safeToFallback = normalized.safeToFallback === true;
    this.submissionAmbiguous = normalized.submissionAmbiguous === true;
    this.httpStatus = Number.isInteger(normalized.httpStatus)
      ? normalized.httpStatus
      : null;
  }
}

export class FalKlingProvider {
  constructor({ apiKey, fetchImpl = fetch }) {
    if (!apiKey || typeof apiKey !== "string") {
      throw new FalProviderError("provider_not_configured", {
        retryable: false,
      });
    }
    this.apiKey = apiKey;
    this.fetchImpl = fetchImpl;
  }

  async submit({
    prompt,
    aspectRatio,
    durationSeconds,
    startImageUrl,
    webhookUrl,
  }) {
    const model = startImageUrl ? IMAGE_MODEL : TEXT_MODEL;
    const url = new URL(`${FAL_QUEUE_ROOT}/${model}`);
    if (webhookUrl) url.searchParams.set("fal_webhook", webhookUrl);

    const body = {
      prompt,
      duration: String(durationSeconds),
      generate_audio: false,
      shot_type: "customize",
      ...(startImageUrl
        ? { start_image_url: startImageUrl }
        : { aspect_ratio: aspectRatio }),
      negative_prompt: NEGATIVE_PROMPT,
      cfg_scale: 0.5,
    };
    let response;
    try {
      response = await this.fetchImpl(url, {
        method: "POST",
        headers: this.#headers(),
        body: JSON.stringify(body),
      });
    } catch {
      // A network error does not prove whether fal accepted the request.
      // Starting another provider could therefore create duplicate videos.
      throw new FalProviderError("provider_transport_ambiguous", {
        retryable: true,
        safeToFallback: false,
        submissionAmbiguous: true,
      });
    }
    const payload = await response.json().catch(() => ({}));
    const requestId = String(payload?.request_id || "");
    if (!response.ok) {
      const safeToFallback = SAFE_FALLBACK_HTTP_STATUSES.has(response.status);
      const submissionAmbiguous = response.status === 408 ||
        response.status >= 500;
      throw new FalProviderError(
        response.status >= 400 && response.status < 500
          ? "provider_rejected"
          : "provider_unavailable",
        {
          retryable: safeToFallback || submissionAmbiguous,
          safeToFallback,
          submissionAmbiguous,
          httpStatus: response.status,
        },
      );
    }
    if (!/^[A-Za-z0-9_-]{8,200}$/.test(requestId)) {
      throw new FalProviderError("provider_response_ambiguous", {
        retryable: true,
        safeToFallback: false,
        submissionAmbiguous: true,
        httpStatus: response.status,
      });
    }
    return {
      requestId,
      kind: startImageUrl ? "image" : "text",
    };
  }

  async status({ requestId, kind }) {
    const response = await this.fetchImpl(
      `${FAL_QUEUE_ROOT}/${modelForKind(kind)}/requests/${
        encodeURIComponent(requestId)
      }/status`,
      { headers: this.#headers(false) },
    );
    if (!response.ok) {
      throw new FalProviderError("provider_unavailable", { retryable: true });
    }
    return mapFalQueueStatus(await response.json().catch(() => ({})));
  }

  async result({ requestId, kind }) {
    const response = await this.fetchImpl(
      `${FAL_QUEUE_ROOT}/${modelForKind(kind)}/requests/${
        encodeURIComponent(requestId)
      }`,
      { headers: this.#headers(false) },
    );
    if (!response.ok) {
      throw new FalProviderError("provider_unavailable", { retryable: true });
    }
    return extractFalVideo(await response.json().catch(() => ({})));
  }

  #headers(withContentType = true) {
    return {
      "Authorization": `Key ${this.apiKey}`,
      ...(withContentType ? { "Content-Type": "application/json" } : {}),
    };
  }
}

export function mapFalQueueStatus(payload) {
  const status = String(payload?.status || "").toUpperCase();
  if (status === "IN_QUEUE") {
    return { status: "queued", progress: 0.05, completed: false };
  }
  if (status === "IN_PROGRESS") {
    return { status: "rendering", progress: 0.5, completed: false };
  }
  if (status === "COMPLETED" && (payload?.error || payload?.error_type)) {
    return {
      status: "failed",
      progress: 1,
      completed: true,
      errorCode: "provider_failed",
    };
  }
  if (status === "COMPLETED") {
    return { status: "completed", progress: 0.9, completed: true };
  }
  throw new FalProviderError("provider_status_invalid", { retryable: true });
}

export function extractFalVideo(payload) {
  const video = payload?.video;
  const url = String(video?.url || "");
  const mimeType = String(video?.content_type || "video/mp4").toLowerCase();
  const byteLength = Number(video?.file_size || 0);
  if (
    !/^https:\/\//i.test(url) ||
    mimeType !== "video/mp4" ||
    !Number.isFinite(byteLength) ||
    byteLength < 0
  ) {
    throw new FalProviderError("provider_result_invalid", { retryable: true });
  }
  return { url, mimeType, byteLength };
}

export function falModelKindFromStartImage(hasStartImage) {
  return hasStartImage ? "image" : "text";
}

function modelForKind(kind) {
  if (kind === "image") return IMAGE_MODEL;
  if (kind === "text") return TEXT_MODEL;
  throw new FalProviderError("provider_model_invalid", { retryable: false });
}
