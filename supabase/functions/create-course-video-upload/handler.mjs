export const APPROVED_DEVELOPER_IDS = Object.freeze([
  "f3eea23f-0aeb-405b-ab35-2c53173b7a8f",
  "eee55a08-18d1-46e3-a303-1411d1bb9333",
]);

export const BUNNY_STREAM_TUS_ENDPOINT = "https://video.bunnycdn.com/tusupload";

const BUNNY_STREAM_API_BASE = "https://video.bunnycdn.com";
const DEFAULT_SIGNATURE_TTL_SECONDS = 24 * 60 * 60;
const MIN_SIGNATURE_TTL_SECONDS = 60 * 60;
const MAX_SIGNATURE_TTL_SECONDS = 24 * 60 * 60;
const MAX_SOURCE_BYTES = 5 * 1024 * 1024 * 1024;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleCreateCourseVideoUpload(request, dependencies) {
  if (dependencies?.releaseEnabled !== true) {
    return json({ error: "video_upload_unavailable" }, 503);
  }

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization") || "";
  if (!/^Bearer\s+\S+/i.test(authorization)) {
    return json({ error: "not_authenticated" }, 401);
  }

  const user = await dependencies.verifyUser(authorization);
  const userID = normalizeUUID(user?.id);
  if (!userID) {
    return json({ error: "not_authenticated" }, 401);
  }

  let input;
  try {
    input = normalizeRequest(await request.json());
  } catch (error) {
    const status = error instanceof CourseVideoUploadRequestError
      ? error.status
      : 400;
    const code = error instanceof CourseVideoUploadRequestError
      ? error.code
      : "invalid_json";
    return json({ error: code }, status);
  }

  if (
    input.purpose === "lesson_video" &&
    (
      !APPROVED_DEVELOPER_IDS.includes(userID) ||
      !(await dependencies.isDeveloper(authorization))
    )
  ) {
    return json({ error: "not_authorized" }, 403);
  }

  const config = normalizeConfig(dependencies.env || {});
  if (!config) {
    dependencies.logger?.error?.(JSON.stringify({
      event: "course_video_upload_not_configured",
      user_id: userID,
    }));
    return json({ error: "video_upload_unavailable" }, 503);
  }

  const leaseToken = normalizeUUID(dependencies.randomUUID?.());
  if (!leaseToken) {
    return json({ error: "video_upload_unavailable" }, 503);
  }
  const requestFingerprint = await sha256Hex(JSON.stringify([
    input.purpose,
    input.resourceID,
    input.fileName,
    input.contentType,
    input.sourceBytes,
  ]));
  const claim = await dependencies.claimUpload(authorization, {
    userID,
    purpose: input.purpose,
    uploadKey: input.uploadKey,
    resourceID: input.resourceID,
    requestFingerprint,
    leaseToken,
  }).catch(() => null);
  if (!claim) {
    return json({ error: "video_upload_unavailable" }, 503);
  }
  if (claim.status === "not_authorized") {
    return json({ error: "not_authorized" }, 403);
  }
  if (claim.status === "rate_limited") {
    return json(
      { error: "rate_limited", retry_after: 60 },
      429,
      { "Retry-After": "60" },
    );
  }
  if (claim.status === "in_progress") {
    return json(
      { error: "upload_slot_in_progress", retry_after: 3 },
      425,
      { "Retry-After": "3" },
    );
  }
  if (claim.status === "idempotency_conflict") {
    return json({ error: "idempotency_conflict" }, 409);
  }

  let videoID = claim.status === "replay" ? normalizeUUID(claim.video_id) : "";
  if (claim.status === "replay" && !videoID) {
    return json({ error: "video_upload_unavailable" }, 503);
  }
  if (claim.status === "claimed") {
    const providerTitle = [
      "X5",
      input.purpose,
      userID,
      input.uploadKey,
      input.resourceID,
    ].join(" ").slice(0, 120);
    if (claim.reclaimed === true) {
      videoID = await findBunnyVideoByTitle(
        dependencies,
        config,
        providerTitle,
      );
      if (!videoID) {
        dependencies.logger?.error?.(JSON.stringify({
          event: "course_video_upload_reconciliation_pending",
          user_id: userID,
        }));
        return json({ error: "video_upload_unavailable" }, 503);
      }
    } else {
      const createResponse = await dependencies.fetchImpl(
        `${BUNNY_STREAM_API_BASE}/library/${config.libraryID}/videos`,
        {
          method: "POST",
          headers: {
            AccessKey: config.apiKey,
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ title: providerTitle }),
          signal: AbortSignal.timeout(10_000),
        },
      ).catch(() => null);

      if (createResponse?.ok) {
        const created = await createResponse.json().catch(() => null);
        videoID = normalizeUUID(created?.guid);
      } else if (!createResponse || createResponse.status >= 500) {
        videoID = await findBunnyVideoByTitle(
          dependencies,
          config,
          providerTitle,
        );
      }
    }

    if (!videoID) {
      dependencies.logger?.error?.(JSON.stringify({
        event: "course_video_upload_create_failed",
        user_id: userID,
      }));
      return json({ error: "video_upload_unavailable" }, 502);
    }

    const completion = await completeUploadWithRetry(
      dependencies,
      authorization,
      {
        uploadKey: input.uploadKey,
        requestFingerprint,
        leaseToken,
        videoID,
      },
    );
    if (!completion) {
      dependencies.logger?.error?.(JSON.stringify({
        event: "course_video_upload_slot_completion_deferred",
        user_id: userID,
        purpose: input.purpose,
      }));
      return json({ error: "video_upload_unavailable" }, 503);
    }
  } else if (claim.status !== "replay") {
    return json({ error: "video_upload_unavailable" }, 503);
  }

  const nowMilliseconds = Number(dependencies.now());
  const nowSeconds = Number.isFinite(nowMilliseconds)
    ? Math.floor(nowMilliseconds / 1_000)
    : Math.floor(Date.now() / 1_000);
  const expires = nowSeconds + config.signatureTTLSeconds;
  const signature = await sha256Hex(
    `${config.libraryID}${config.apiKey}${expires}${videoID}`,
  );
  const playbackURL = `https://${config.cdnHostname}/${videoID}/playlist.m3u8`;
  const uploadHeaders = {
    AuthorizationSignature: signature,
    AuthorizationExpire: String(expires),
    LibraryId: config.libraryID,
    VideoId: videoID,
  };

  return json({
    tus_endpoint: BUNNY_STREAM_TUS_ENDPOINT,
    video_id: videoID,
    library_id: config.libraryID,
    authorization_signature: signature,
    authorization_expire: expires,
    upload_headers: uploadHeaders,
    playback_url: playbackURL,
  });
}

class CourseVideoUploadRequestError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.name = "CourseVideoUploadRequestError";
    this.code = code;
    this.status = status;
  }
}

function normalizeRequest(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new CourseVideoUploadRequestError("invalid_request");
  }

  const purpose = value.purpose === "lesson_video" ||
      value.purpose === "course_submission"
    ? value.purpose
    : "";
  const uploadKey = normalizeText(value.upload_key, 16, 128);
  const resourceID = normalizeText(value.resource_id, 1, 160);
  const title = normalizeText(value.title, 1, 120);
  const fileName = normalizeText(value.file_name, 1, 255);
  const contentType = normalizeText(value.content_type, 1, 128)
    .toLowerCase();
  const sourceBytes = Number(value.source_bytes);

  if (
    !purpose ||
    !/^[A-Za-z0-9_-]+$/.test(uploadKey) ||
    !/^[A-Za-z0-9._:-]+$/.test(resourceID) ||
    !title ||
    !fileName ||
    !/^video\/[a-z0-9.+-]+$/i.test(contentType) ||
    !Number.isSafeInteger(sourceBytes) ||
    sourceBytes <= 0 ||
    sourceBytes > MAX_SOURCE_BYTES
  ) {
    throw new CourseVideoUploadRequestError("invalid_request");
  }

  return {
    purpose,
    uploadKey,
    resourceID,
    title,
    fileName,
    contentType,
    sourceBytes,
  };
}

function normalizeConfig(env) {
  const libraryID = String(env.BUNNY_STREAM_LIBRARY_ID || "").trim();
  const apiKey = String(env.BUNNY_STREAM_API_KEY || "").trim();
  const cdnHostname = String(env.BUNNY_STREAM_CDN_HOSTNAME || "")
    .trim()
    .toLowerCase();
  if (
    !/^[1-9][0-9]*$/.test(libraryID) ||
    !apiKey ||
    !isSafeHostname(cdnHostname)
  ) {
    return null;
  }

  const rawTTL = String(env.BUNNY_STREAM_TUS_TTL_SECONDS ?? "").trim();
  const requestedTTL = rawTTL ? Number(rawTTL) : Number.NaN;
  const signatureTTLSeconds = Number.isFinite(requestedTTL)
    ? Math.min(
      MAX_SIGNATURE_TTL_SECONDS,
      Math.max(MIN_SIGNATURE_TTL_SECONDS, Math.floor(requestedTTL)),
    )
    : DEFAULT_SIGNATURE_TTL_SECONDS;

  return { libraryID, apiKey, cdnHostname, signatureTTLSeconds };
}

async function findBunnyVideoByTitle(
  dependencies,
  config,
  providerTitle,
) {
  const url = new URL(
    `${BUNNY_STREAM_API_BASE}/library/${config.libraryID}/videos`,
  );
  url.searchParams.set("page", "1");
  url.searchParams.set("itemsPerPage", "100");
  url.searchParams.set("search", providerTitle);

  const response = await dependencies.fetchImpl(url, {
    method: "GET",
    headers: {
      AccessKey: config.apiKey,
      Accept: "application/json",
    },
    signal: AbortSignal.timeout(6_000),
  }).catch(() => null);
  if (!response?.ok) return "";

  const payload = await response.json().catch(() => null);
  if (!payload || !Array.isArray(payload.items)) return "";
  const matches = payload.items.filter((item) =>
    item?.title === providerTitle && normalizeUUID(item?.guid)
  );
  if (matches.length !== 1) return "";
  return normalizeUUID(matches[0].guid);
}

function isSafeHostname(value) {
  if (
    !value ||
    value.length > 253 ||
    value === "localhost" ||
    !value.endsWith(".b-cdn.net") ||
    /^[0-9.]+$/.test(value)
  ) {
    return false;
  }
  return value.split(".").every((label) =>
    /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)
  );
}

function normalizeText(value, minimumLength, maximumLength) {
  if (typeof value !== "string") return "";
  const normalized = value.trim().replace(/\s+/g, " ");
  if (
    normalized.length < minimumLength ||
    normalized.length > maximumLength
  ) {
    return "";
  }
  return normalized;
}

function normalizeUUID(value) {
  if (typeof value !== "string") return "";
  const normalized = value.trim().toLowerCase();
  return UUID_PATTERN.test(normalized) ? normalized : "";
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function completeUploadWithRetry(
  dependencies,
  authorization,
  input,
) {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const result = await dependencies.completeUpload(
      authorization,
      input,
    ).catch(() => null);
    if (
      result?.status === "completed" ||
      result?.status === "already_completed"
    ) {
      return result;
    }
    if (attempt < 2) {
      await new Promise((resolve) => setTimeout(resolve, 100 * (attempt + 1)));
    }
  }
  return null;
}

function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}
