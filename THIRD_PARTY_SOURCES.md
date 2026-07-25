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
  resumable upload when the source exceeds Supabase Free's global Storage
  limit.

The package is pinned rather than floating. This commit has a passing upstream
CodeQL scan and includes fixes for failed video-output setup, scaling,
long-export memory use and temporary-file cleanup. It uses Apple's AVFoundation
reader/writer pipeline, supports iOS 16+, exposes bitrate and output-dimension
controls, and does not add a network or analytics layer. X5 targets iOS 16,
forces web-compatible SDR H.264 output, and checks the exported byte size and
full duration before any server request.
