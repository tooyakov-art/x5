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
