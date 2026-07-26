# Third-party sources

## TUSKit

- Upstream source: https://github.com/tus/TUSKit
- Upstream version: 3.7.1
- Upstream commit: `167938293923b5c31ba1255da5aada8e67533984`
- Pinned fork: https://github.com/tooyakov-art/TUSKit
- Pinned patch commit: `4fd278f37b8a20f826a6fa45ae12b18b47b058b6`
- License: MIT; preserved at `X5/Resources/ThirdParty/TUSKit-LICENSE.txt`
- Use: resumable, chunked uploads of course and course-submission videos to
  Supabase Storage.

The fork contains two audited compatibility patches: TUS requests use the
`URLSessionConfiguration.timeoutIntervalForRequest` supplied by the app instead
of overriding it with a hard-coded 30-second timeout, and callers can keep
dynamically generated authorization headers transient instead of serializing
them into resumable-upload metadata. The transient mode also removes
case-insensitive legacy `Authorization` entries left by older app builds before
resolving or re-saving upload metadata. The app configures 300 seconds and
regenerates its short-lived Supabase token for each request. No protocol,
storage or server API behavior is otherwise changed.

## NextLevelSessionExporter

- Source: https://github.com/NextLevel/NextLevelSessionExporter
- Version: post-1.0.1 audited main snapshot
- Pinned commit: `1bb6e19731ff512f4652f8ce2a8f67c779b1598f`
- License: MIT; preserved at
  `X5/Resources/ThirdParty/NextLevelSessionExporter-LICENSE.txt`
- Use: local H.264/AAC transcoding of user-selected course videos before
  resumable upload when the source exceeds Supabase Free's global Storage limit.

The package is pinned rather than floating. This commit has a passing upstream
CodeQL scan and includes fixes for failed video-output setup, scaling,
long-export memory use and temporary-file cleanup. It uses Apple's AVFoundation
reader/writer pipeline, supports iOS 16+, exposes bitrate and output-dimension
controls, and does not add a network or analytics layer. X5 targets iOS 16,
forces web-compatible SDR H.264 output, and checks the exported byte size and
full duration before any server request.

## Hosted AI APIs

The following services are called only from Supabase Edge Functions. No SDK,
model weights, provider branding, sample media, or proprietary source code is
bundled in the app.

### fal Kling Video V3 Standard

- Official API reference:
  https://fal.ai/models/fal-ai/kling-video/v3/standard/text-to-video/api
- Image-to-video and text-to-video endpoint reference:
  https://fal.ai/docs/model-api-reference/video-generation-api/kling-video-v3-standard
- Retrieved: 2026-07-26
- Use: primary asynchronous 5- or 10-second video generation through the fal
  queue and signed webhook flow.
- Integration: server-side HTTP contract adapted to the documented queue
  submit/status/result API. `FAL_KEY` is never included in the iOS binary.

### Google Gemini Omni Flash

- Official model card:
  https://ai.google.dev/gemini-api/docs/models/gemini-omni-flash
- Official video-generation guide: https://ai.google.dev/gemini-api/docs/video
- Official Interactions API and dynamic webhook references:
  https://ai.google.dev/api/interactions-api
  https://ai.google.dev/gemini-api/docs/webhooks
- Retrieved: 2026-07-26
- Use: configured server-side fallback for short text-to-video and
  image-to-video generation when fal returns an explicitly fallback-safe
  availability response.
- Integration: server-side Interactions API only. Background requests include a
  request-scoped dynamic callback carrying only an opaque job UUID and one-time
  claim token. Callbacks are authenticated with Google's documented RS256 JWKS
  signature, strict audience/time checks, and an atomic hash-bound database RPC.
  The documented `video.generated` `output_file_uri`/`file_name` result is used
  only after a Google-host allowlist check. Reconciliation also supports the
  documented behavior where a GET interaction returns inline base64 even when
  the original request used URI delivery; that field is decoded while streaming
  under the generated-video byte limit rather than raising the generic one-MiB
  JSON cap. A submit-time `429 RESOURCE_EXHAUSTED` is treated as a known
  rejection and refunded, while transport/408/5xx ambiguity stays reserved for
  reconciliation. Google API credentials are never included in the iOS binary.

### OpenAI Responses and Moderations

- Official Responses API reference:
  https://platform.openai.com/docs/api-reference/responses
- Official Moderations API reference:
  https://platform.openai.com/docs/api-reference/moderations
- Retrieved: 2026-07-26
- Use: Startup Chat responses, the structured Live Fruits storyboard, and
  automatic safety screening of text and selected reference images before AI
  video generation or storyboard creation.
- Integration: server-side requests use `store: false` where supported.
  `OPENAI_API_KEY` is never included in the iOS binary.

### OpenAI Videos (Sora 2)

- Official Videos API reference:
  https://developers.openai.com/api/reference/resources/videos
- Official Sora 2 model card:
  https://developers.openai.com/api/docs/models/sora-2
- Retrieved: 2026-07-26
- Use: final server-side fallback for short text-to-video and image-to-video
  jobs when Google's submit is definitively rejected before acceptance.
- Integration: X5 keeps its 5/10-second product choices and maps them to the
  provider's supported 4/8-second values. Status is polled by opaque video ID;
  completed bytes are downloaded from the authenticated content endpoint,
  bounded to the same private-video limit, and copied into private X5 Storage.
  Transport failures, HTTP 408, and HTTP 5xx stay submission-ambiguous and never
  start a second provider request. `OPENAI_API_KEY` remains server-only.
