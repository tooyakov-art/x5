# Bunny Stream course video upload quarantine

## Release quarantine

This directory preserves an unfinished Bunny Stream upload prototype for future
work. It is not a build-192 feature and must not be deployed or enabled.

The release is intentionally closed in three independent places:

1. The iOS route is compiled only with `X5_ENABLE_BUNNY_COURSE_VIDEO_UPLOAD`.
   Build 192 does not define that compilation condition, so lesson and
   submission videos continue through the existing Supabase preparation/upload
   path and its existing size boundary.
2. `index.ts` passes a hard-coded
   `BUNNY_COURSE_VIDEO_UPLOAD_RELEASE_ENABLED = false` gate. The handler returns
   `503 video_upload_unavailable` before authentication, upload-slot RPCs,
   provider calls, or signature generation.
3. The draft migration revokes function execution from `public`, `anon`, and
   `authenticated`. Applying it accidentally therefore does not expose either
   upload-slot RPC to an authenticated client.

The current Supabase migrations set the `videos` and `course-media` bucket
metadata limit to 5 GiB and mark those buckets public. That is neither
entitlement-protected playback nor proof that the app, gateway, project quota,
timeouts, and resumable recovery support a 5 GiB end-to-end upload. Do not cite
that database limit as a shipped secure long-video feature.

Bunny project secrets are intentionally not configured. Do not add
`BUNNY_STREAM_LIBRARY_ID`, `BUNNY_STREAM_API_KEY`, or
`BUNNY_STREAM_CDN_HOSTNAME` to production while this quarantine is in place.
Never put `BUNNY_STREAM_API_KEY` in the iOS project, Info.plist, build settings,
CI artifacts, analytics, logs, or a client response.

## Blockers before any future enablement

The preserved prototype is not release-ready. A future implementation needs a
new security and lifecycle review covering all of the following:

- entitlement-checked, short-lived playback instead of a permanent public HLS
  URL that can bypass course purchase access;
- a coordinated migration away from current public Supabase course-video URLs,
  including every native/web/Android reader and rollback behavior;
- provider processing/readiness state, including failure and timeout handling,
  before a URL can be saved or shown;
- video moderation before publication;
- cleanup for failed, abandoned, replaced, rejected, and account-deletion
  objects, plus operator reconciliation for ambiguous provider calls;
- a server-only RPC broker. Authenticated clients must never receive direct
  `EXECUTE` on the security-definer upload ledger functions;
- provider credentials, staging configuration, cost/rate limits, operational
  monitoring, and representative interrupted-upload tests.

Only after those blockers are implemented and red-teamed should a separate
release intentionally change the server constant, add the Swift compilation
condition, configure fresh Bunny secrets, and update release metadata. The
current source-level tests exercise dormant mechanics only; they do not claim
that 1 GiB uploads, Bunny playback, readiness, moderation, or cleanup ship in
build 192.

## Preserved references

- Bunny Stream resumable uploads:
  https://docs.bunny.net/stream/tus-resumable-uploads
- Bunny Stream create/list video API:
  https://docs.bunny.net/api-reference/stream/manage-videos/create-video
  https://docs.bunny.net/api-reference/stream/manage-videos/list-videos
