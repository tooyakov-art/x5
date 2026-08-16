# Third-party sources

## GeoNames CIS city dataset

- Source: https://download.geonames.org/export/dump/
- License: Creative Commons Attribution 4.0.
- Retrieved: 2026-08-10.
- Use: searchable country and city selection during onboarding and task creation.
- Bundled derivative: `X5/Resources/cis-cities.json`, filtered to the 12 supported CIS and Russian-speaking country codes.

## Client-supplied Home artwork

### Client-selected Instagram Trend clips

- Selection/instruction date: 2026-08-16.
- Strawberry source: `https://www.instagram.com/reel/DXoWkuziCX6/`.
- Tokayev source: `https://www.instagram.com/reel/C8RAdTZtCoT/`.
- Bundled derivatives: `HomeTrendStrawberry.mp4` and `HomeTrendTokayev.mp4`.
- Transform: audio removed; H.264/yuv420p fast-start transcode. The strawberry Reel is placed over a blurred vertical canvas without removing its original frame; the Tokayev Reel retains its vertical frame.
- Use: muted, looping Home Trend previews and matching poster frames.
- Rights boundary: the X5 owner/client expressly instructed the app team to use these specific Reels. This project record is not evidence of a copyright assignment or endorsement by Instagram, the uploaders, or depicted people; public-release clearance remains the owner's responsibility.

### Nano Banana + GPT Image trend card

- Supplied directly by the client on 2026-07-26 with an explicit request to
  use it in place of the previous Home artwork.
- Bundled asset:
  `X5/Assets.xcassets/HomeTrendNanoBanana.imageset/HomeTrendNanoBanana.jpg`
- Use: static Home trend card linking to the existing image generator.
- Provenance: client-supplied finished artwork; X5 did not generate or claim
  authorship of the image.
- Release condition: the artwork includes third-party product names and marks.
  The client's ownership and public/commercial-use rights must be confirmed
  before external release. No third-party endorsement is implied.

## Pexels Home motion clips

- Pexels license: https://www.pexels.com/legal-pages/license/
- Retrieved: 2026-07-26
- Use: short, muted motion backgrounds on the X five marketing Home screen.
- App transforms: each selected source was trimmed to six seconds, resized to
  960 x 540, transcoded to H.264, and had audio removed.
  Matching local JPEG posters provide the no-motion and playback-failure
  fallback.

### Digital Projection Of Abstract Geometrical Lines

- Creator: Pressmaster
- Source page:
  https://www.pexels.com/video/digital-projection-of-abstract-geometrical-lines-3129671/
- Selected official Pexels file:
  https://videos.pexels.com/video-files/3129671/3129671-hd_1280_720_30fps.mp4
- Bundled derivative: `X5/Resources/HomeMotion/HomeMotionStudio.mp4`
- Poster derivative:
  `X5/Assets.xcassets/HomeMotionStudioPoster.imageset/HomeMotionStudioPoster.jpg`

### Close-Up View of Fruits in a Bowl

- Creator: www.kaboompics.com
- Source page:
  https://www.pexels.com/video/close-up-view-of-fruits-in-a-bowl-6989164/
- Selected official Pexels file:
  https://videos.pexels.com/video-files/6989164/6989164-uhd_4096_2160_25fps.mp4
- Bundled derivative: `X5/Resources/HomeMotion/HomeMotionFruit.mp4`
- Poster derivative:
  `X5/Assets.xcassets/HomeMotionFruitPoster.imageset/HomeMotionFruitPoster.jpg`

## Higgsfield debug-only Home demo references

- Retrieved: 2026-07-29.
- Scope: temporary client review in local Xcode Debug builds only.
- Delivery: the files are streamed from the public source URLs. They are not bundled,
  copied into the repository, or redistributed with the app.
- Release boundary: `HomeDemoConfiguration` always disables these references in
  Release builds. Set the Xcode environment variable `X5_HOME_DEMO_MODE=0` to
  disable them in Debug as well.

### Seedream 5.0 Pro image-generation demo

- Source page: https://higgsfield.ai/ai/image?model=seedream_v5_pro
- Public landing media:
  https://cdn.higgsfield.ai/card/83522493-66ba-44b9-92f6-ae18cd8ba22b.mp4
- Verified landing label: `ByteDance's top-tier reasoning image model`.
- Use: image-generation hero only. It must not be labelled as video generation,
  Supercomputer, Academy, After Effects, or App Contest.

### Higgsfield AI Video Generator demo

- Source page: https://higgsfield.ai/ai-video
- Public landing media:
  https://static.higgsfield.ai/ai-video-v2/01-mini.mp4
- Verified page role: the AI Video Generator demonstration for text-to-video
  and image-to-video models.
- Use: video-generation cards only. It must not be labelled as image generation.

### Higgsfield Create Audio demo

- Source page: https://higgsfield.ai/
- Public landing media:
  https://static.higgsfield.ai/flow-medias/create-audio-22-07-2026.mp4
- Verified landing role: `AI voiceovers & voice change`.
- Use: voiceover and voice-generation hero only. It is a visual demo reference;
  it does not claim that Higgsfield is the production voice provider.

## X5-owned Higgsfield Home exports

- Provider terms: https://higgsfield.ai/terms-of-use-agreement
- Terms verified: 2026-08-01; section 4.4 states that Higgsfield does not claim
  ownership of user outputs and does not restrict their commercial use.
- Rights boundary: this applies only to outputs generated by the X5 account
  from inputs and likenesses X5 is entitled to use.
- Delivery: existing project objects in the X5 Supabase `videos/home` bucket;
  the app permits only that HTTPS host and retains the approved client artwork
  as its offline poster.
- Selected release fallbacks: `ai-stylist.mp4` and `face-swap.mp4`. The older
  `transitions.mp4` and `lipsync.mp4` previews were removed because they did not
  match the visible client-selected Trend cards.
- Performance/accessibility: Home instantiates one active muted player at a
  time; offscreen, background, Low Power Mode, and Reduce Motion states pause
  playback.
- Exact mapping and visual limitations are recorded in
  `docs/home-media-provenance.md`.

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

### fal ByteDance Seedance 1.5 Pro

- Official combined text-to-video and image-to-video API reference:
  https://fal.ai/docs/model-api-reference/video-generation-api/bytedance-seedance-v1.5-pro
- Official text-to-video API:
  https://fal.ai/models/fal-ai/bytedance/seedance/v1.5/pro/text-to-video/api
- Official image-to-video API:
  https://fal.ai/models/fal-ai/bytedance/seedance/v1.5/pro/image-to-video/api
- Retrieved: 2026-07-26
- Use: explicit 5- or 10-second Seedance text-to-video and image-to-video jobs
  with 480p, 720p, or 1080p output and optional native audio.
- Integration: the existing server-side fal queue, signed webhook, private input
  and exact-once credit flow is reused. X5 always sends
  `enable_safety_checker: true`; that setting is not client-controlled. An
  explicit Seedance request never silently falls back to a different model.
  `FAL_KEY` remains server-only and is never included in the iOS binary.

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

### fal ElevenLabs TTS Eleven v3

- Official API reference:
  https://fal.ai/models/fal-ai/elevenlabs/tts/eleven-v3
- Official queue lifecycle:
  https://fal.ai/docs/documentation/model-apis/inference/queue
- Official webhook delivery and signature verification:
  https://fal.ai/docs/documentation/model-apis/inference/webhooks
- Official storage/lifecycle request headers:
  https://fal.ai/docs/documentation/model-apis/common-parameters
- Retrieved: 2026-07-26; model API reverified: 2026-08-01
- Use: server-side speech generation from user-supplied text with a selected
  voice, stability, speed, and optional language hint.
- Integration: X5 submits once to fal's persistent queue and correlates the
  provider request ID with an exact-once credit ledger. The callback verifies
  fal's Ed25519 signature over the untouched request bytes; callback and client
  retries reuse the same job instead of generating twice. Provider persistence
  is disabled with `X-Fal-Store-IO: 0`, generated provider objects request a
  three-hour lifecycle, and `FAL_KEY` remains server-only. The returned MP3 is
  size- and type-checked, copied into private owner-scoped X5 Storage, and
  exposed to the app through a short-lived signed URL that is immediately
  downloaded into an app-managed local file for playback and sharing.

## Push delivery infrastructure

### Supabase JavaScript client and Deno JWT

- Supabase JS source/version: https://github.com/supabase/supabase-js/tree/v2.110.3
- Deno djwt source/version: https://github.com/Zaubrik/djwt/tree/v3.0.2
- Versions: `@supabase/supabase-js` 2.110.3; `djwt` 3.0.2.
- Licenses: MIT for both projects; no attribution UI is required. Verified:
  2026-08-01.
- Integration: exact versions are imported only by server-side Edge Functions.
  The affected function folders contain frozen Deno v5 lockfiles with npm
  SHA-512 integrity values and remote-module hashes. Supabase JS performs
  canonical database/RPC access; djwt signs APNs and Google OAuth assertions.
  No dependency is shipped in the mobile app.

### Supabase private Storage and signed URLs

- Official access-control guide:
  https://supabase.com/docs/guides/storage/security/access-control
- Official signed URL API:
  https://supabase.com/docs/reference/javascript/storage-from-createsignedurl
- Verified: 2026-08-01.
- Integration: `chat-media` and `portfolio` are private buckets. Database rows
  retain canonical object identifiers; authorized clients request short-lived
  signed URLs. Rejected portfolio media and stale orphans are deleted through
  the Storage API, not by mutating `storage.objects` directly.

### Apple Push Notification service

- Official provider-server guide:
  https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server
- Official request contract:
  https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
- Verified: 2026-08-01
- Service: Apple-hosted APNs; no Apple SDK source or redistributable asset is
  bundled for the server path.
- Integration: the server uses token authentication, a UUID `apns-id`, and a
  bounded `apns-collapse-id`. Keys remain server-only.

### Firebase Cloud Messaging HTTP v1

- Official HTTP v1 send and OAuth guide:
  https://firebase.google.com/docs/cloud-messaging/send/v1-api
- Official server-environment guide:
  https://firebase.google.com/docs/cloud-messaging/server-environment
- Verified: 2026-08-01
- Documentation/code-sample terms: Google documentation is CC BY 4.0 and its
  samples are Apache 2.0; this integration reuses the protocol, not copied SDK
  source.
- Integration: the server mints a short-lived OAuth token from a dedicated
  service account and calls the project-scoped HTTP v1 endpoint. The retired
  legacy server-key endpoint is not used, and the service-account JSON remains
  server-only.

## Course video delivery

### Bunny Stream direct TUS uploads

- Official resumable-upload reference:
  https://docs.bunny.net/stream/tus-resumable-uploads
- Official create/list video references:
  https://docs.bunny.net/api-reference/stream/manage-videos/create-video
  https://docs.bunny.net/api-reference/stream/manage-videos/list-videos
- Retrieved: 2026-07-26
- Service: Bunny Stream is a commercial hosted service governed by Bunny's
  service terms; no Bunny SDK or provider source code is bundled.
- Status: quarantined future source only. Build 192 does not compile or route
  user uploads through Bunny, the server handler is hard-disabled, the draft
  RPCs are unavailable to API-facing roles, and Bunny secrets are not
  configured.
- Planned use: direct resumable upload after private entitlement-checked
  playback, provider readiness, moderation, cleanup, and server-only ledger
  access are implemented and reviewed. The preserved prototype's public HLS
  response is not release-safe and must not be enabled as written.

## Kaspi Pay provider integration

- Official Kaspi Pay overview:
  https://kaspi.kz/kaspipay
- Official provider protocol and exact-amount payment URL format:
  https://guide.kaspi.kz/cdn/content/pay/product/documents/Instrukciya-po-integracii-1C-s-servisom-Platezhi-na-Kaspi-kz-dlya-distribyutorov.pdf
- Official remote-payment guide:
  https://guide.kaspi.kz/partner/ru/pos/payments/remote/q2098
- Verified: 2026-08-13
- Integration: the server creates an immutable KZT order and uses only the
  Kaspi-issued `serviceName`, `serviceId`, and account parameter. The provider
  `check`/`pay` callback grants credits atomically and idempotently. A normal
  Kaspi Pay POS link is not substituted because it requires the buyer to enter
  the amount manually.
