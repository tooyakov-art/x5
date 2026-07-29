// deno-lint-ignore-file require-await
// Async stubs deliberately model the production network/RPC dependency shape.
import assert from "node:assert/strict";
import test from "node:test";

const moduleURL = new URL("./handler.mjs", import.meta.url);
let backend;
try {
  backend = await import(moduleURL);
} catch {
  backend = null;
}

test("course video upload handler exists", () => {
  assert.ok(
    backend,
    "create-course-video-upload handler must be implemented",
  );
});

test("release gate defaults closed before auth, RPC, or Bunny calls", async () => {
  assert.ok(backend);
  let verified = false;
  let claimed = false;
  let bunnyCalled = false;
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      releaseEnabled: undefined,
      verifyUser: async () => {
        verified = true;
        return null;
      },
      claimUpload: async () => {
        claimed = true;
        return null;
      },
      fetchImpl: async () => {
        bunnyCalled = true;
        throw new Error("unexpected");
      },
    }),
  );
  const payload = await response.json();

  assert.equal(response.status, 503);
  assert.deepEqual(payload, { error: "video_upload_unavailable" });
  assert.equal(verified, false);
  assert.equal(claimed, false);
  assert.equal(bunnyCalled, false);
});

test("rejects a missing bearer token before authorization or Bunny calls", async () => {
  assert.ok(backend);
  let verified = false;
  let bunnyCalled = false;
  const response = await backend.handleCreateCourseVideoUpload(
    new Request(
      "https://example.test/functions/v1/create-course-video-upload",
      {
        method: "POST",
        body: JSON.stringify(validBody()),
      },
    ),
    dependencies({
      verifyUser: async () => {
        verified = true;
        return null;
      },
      fetchImpl: async () => {
        bunnyCalled = true;
        throw new Error("unexpected");
      },
    }),
  );

  assert.equal(response.status, 401);
  assert.equal(verified, false);
  assert.equal(bunnyCalled, false);
});

test("requires both the exact immutable account allowlist and the server RPC", async () => {
  assert.ok(backend);
  let bunnyCalled = false;
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      verifyUser: async () => ({
        id: "9ae99a45-91ac-486a-b7ec-e6614b7bc257",
      }),
      isDeveloper: async () => true,
      fetchImpl: async () => {
        bunnyCalled = true;
        throw new Error("unexpected");
      },
    }),
  );

  assert.equal(response.status, 403);
  assert.equal(bunnyCalled, false);
});

test("fails closed when the exact account is not approved by server RPC", async () => {
  assert.ok(backend);
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      verifyUser: async () => ({
        id: "f3eea23f-0aeb-405b-ab35-2c53173b7a8f",
      }),
      isDeveloper: async () => false,
    }),
  );

  assert.equal(response.status, 403);
});

test("future opt-in source can claim an owner submission slot", async () => {
  assert.ok(backend);
  let developerGateCalled = false;
  let claimed;
  const response = await backend.handleCreateCourseVideoUpload(
    request({
      ...validBody(),
      purpose: "course_submission",
      resource_id: "submission-draft-42",
    }),
    dependencies({
      verifyUser: async () => ({
        id: "9ae99a45-91ac-486a-b7ec-e6614b7bc257",
      }),
      isDeveloper: async () => {
        developerGateCalled = true;
        return false;
      },
      claimUpload: async (authorization, input) => {
        claimed = { authorization, input };
        return {
          status: "claimed",
          lease_token: "123e4567-e89b-42d3-a456-426614174001",
        };
      },
      fetchImpl: async () =>
        Response.json({
          guid: "123e4567-e89b-42d3-a456-426614174000",
        }),
    }),
  );

  assert.equal(response.status, 200);
  assert.equal(developerGateCalled, false);
  assert.equal(claimed.input.purpose, "course_submission");
  assert.equal(
    claimed.input.userID,
    "9ae99a45-91ac-486a-b7ec-e6614b7bc257",
  );
});

test("returns safe 503 before Bunny when server credentials are missing", async () => {
  assert.ok(backend);
  let bunnyCalled = false;
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      env: {
        BUNNY_STREAM_LIBRARY_ID: "",
        BUNNY_STREAM_API_KEY: "",
        BUNNY_STREAM_CDN_HOSTNAME: "",
      },
      fetchImpl: async () => {
        bunnyCalled = true;
        throw new Error("unexpected");
      },
    }),
  );
  const payload = await response.json();

  assert.equal(response.status, 503);
  assert.equal(payload.error, "video_upload_unavailable");
  assert.equal(JSON.stringify(payload).includes("BUNNY_STREAM"), false);
  assert.equal(bunnyCalled, false);
});

test("rejects a non-Bunny CDN hostname before creating a video", async () => {
  assert.ok(backend);
  let bunnyCalled = false;
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      env: {
        BUNNY_STREAM_LIBRARY_ID: "321",
        BUNNY_STREAM_API_KEY: "test-stream-key",
        BUNNY_STREAM_CDN_HOSTNAME: "media.example.com",
      },
      fetchImpl: async () => {
        bunnyCalled = true;
        throw new Error("unexpected");
      },
    }),
  );

  assert.equal(response.status, 503);
  assert.equal(bunnyCalled, false);
});

test("future opt-in source builds the provider TUS contract", async () => {
  assert.ok(backend);
  const requests = [];
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      fetchImpl: async (url, init) => {
        requests.push({ url: String(url), init });
        return Response.json({
          guid: "123e4567-e89b-42d3-a456-426614174000",
          libraryId: 321,
          title: "Course lesson",
        });
      },
    }),
  );
  const payload = await response.json();
  const expectedSignature = await sha256Hex(
    "321test-stream-key1900086400123e4567-e89b-42d3-a456-426614174000",
  );

  assert.equal(response.status, 200);
  assert.equal(requests.length, 1);
  assert.equal(
    requests[0].url,
    "https://video.bunnycdn.com/library/321/videos",
  );
  assert.equal(requests[0].init.method, "POST");
  assert.equal(requests[0].init.headers.AccessKey, "test-stream-key");
  assert.deepEqual(JSON.parse(requests[0].init.body), {
    title:
      "X5 lesson_video f3eea23f-0aeb-405b-ab35-2c53173b7a8f 0123456789abcdef0123456789abcdef course-1-lesson-1",
  });
  assert.equal(payload.tus_endpoint, "https://video.bunnycdn.com/tusupload");
  assert.equal(payload.video_id, "123e4567-e89b-42d3-a456-426614174000");
  assert.equal(payload.library_id, "321");
  assert.equal(payload.authorization_expire, 1_900_086_400);
  assert.equal(payload.authorization_signature, expectedSignature);
  assert.deepEqual(payload.upload_headers, {
    AuthorizationSignature: expectedSignature,
    AuthorizationExpire: "1900086400",
    LibraryId: "321",
    VideoId: "123e4567-e89b-42d3-a456-426614174000",
  });
  assert.equal(
    payload.playback_url,
    "https://x5-stream.b-cdn.net/123e4567-e89b-42d3-a456-426614174000/playlist.m3u8",
  );
  assert.equal("embed_url" in payload, false);
});

test("future opt-in source replays an owned slot without another object", async () => {
  assert.ok(backend);
  let bunnyCalled = false;
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      claimUpload: async () => ({
        status: "replay",
        video_id: "123e4567-e89b-42d3-a456-426614174000",
      }),
      fetchImpl: async () => {
        bunnyCalled = true;
        throw new Error("unexpected");
      },
    }),
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.equal(bunnyCalled, false);
  assert.equal(payload.video_id, "123e4567-e89b-42d3-a456-426614174000");
});

test("future opt-in source reconciles an ambiguous create by exact title", async () => {
  assert.ok(backend);
  const requests = [];
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      fetchImpl: async (url, init) => {
        requests.push({ url: String(url), init });
        if (init.method === "POST") {
          throw new TypeError("connection closed after request body");
        }
        return Response.json({
          items: [{
            guid: "123e4567-e89b-42d3-a456-426614174000",
            title:
              "X5 lesson_video f3eea23f-0aeb-405b-ab35-2c53173b7a8f 0123456789abcdef0123456789abcdef course-1-lesson-1",
          }],
        });
      },
    }),
  );
  const payload = await response.json();

  assert.equal(response.status, 200);
  assert.equal(payload.video_id, "123e4567-e89b-42d3-a456-426614174000");
  assert.equal(
    requests.filter((entry) => entry.init.method === "POST").length,
    1,
  );
  assert.equal(
    requests.filter((entry) => entry.init.method === "GET").length,
    1,
  );
});

test("future opt-in source never duplicates a reclaimed ambiguous slot", async () => {
  assert.ok(backend);
  const requests = [];
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      claimUpload: async () => ({
        status: "claimed",
        reclaimed: true,
      }),
      fetchImpl: async (url, init) => {
        requests.push({ url: String(url), init });
        return Response.json({ items: [] });
      },
    }),
  );

  assert.equal(response.status, 503);
  assert.equal(
    requests.filter((entry) => entry.init.method === "POST").length,
    0,
  );
  assert.equal(
    requests.filter((entry) => entry.init.method === "GET").length,
    1,
  );
});

test("does not expose the Bunny key when video creation fails", async () => {
  assert.ok(backend);
  const response = await backend.handleCreateCourseVideoUpload(
    request(validBody()),
    dependencies({
      fetchImpl: async () =>
        new Response(
          JSON.stringify({ message: "provider saw test-stream-key" }),
          { status: 502 },
        ),
    }),
  );
  const text = await response.text();

  assert.equal(response.status, 502);
  assert.equal(text.includes("test-stream-key"), false);
  assert.match(text, /video_upload_unavailable/);
});

function request(body) {
  return new Request(
    "https://example.test/functions/v1/create-course-video-upload",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer developer-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
}

function validBody() {
  return {
    purpose: "lesson_video",
    upload_key: "0123456789abcdef0123456789abcdef",
    resource_id: "course-1-lesson-1",
    title: "Course lesson",
    file_name: "lesson.mov",
    content_type: "video/quicktime",
    source_bytes: 1_073_741_824,
  };
}

function dependencies(overrides = {}) {
  return {
    // Tests below exercise dormant source explicitly. Production index.ts
    // passes a hard-coded false release gate.
    releaseEnabled: true,
    env: {
      BUNNY_STREAM_LIBRARY_ID: "321",
      BUNNY_STREAM_API_KEY: "test-stream-key",
      BUNNY_STREAM_CDN_HOSTNAME: "x5-stream.b-cdn.net",
    },
    now: () => 1_900_000_000_000,
    verifyUser: async () => ({
      id: "f3eea23f-0aeb-405b-ab35-2c53173b7a8f",
    }),
    isDeveloper: async () => true,
    claimUpload: async () => ({
      status: "claimed",
      lease_token: "123e4567-e89b-42d3-a456-426614174001",
    }),
    completeUpload: async () => ({ status: "completed" }),
    randomUUID: () => "123e4567-e89b-42d3-a456-426614174001",
    fetchImpl: async () => {
      throw new Error("unexpected Bunny request");
    },
    ...overrides,
  };
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
