# Changelog

All notable changes are recorded here. Dates are ISO-8601.

## Unreleased — 2026-05

### Added
- **Mirror-aggregating catalogue + torrent layer** (`PopcornKit/Sources/Managers/MirrorAggregator.swift`).
  Every catalogue listing and detail request fans out across all known
  Popcorn API mirrors in parallel via `withTaskGroup`, then merges:
  catalogue lists are deduped by IMDb id (first mirror's order wins,
  uniques from the rest are appended); torrents are unioned by URL with
  the highest seed count winning. `Popcorn.fallbackMirrors` hardcodes
  `[uxert, fusme, jfper, yrkde].link` so we never strand on a single
  mirror when the DHT discovery worker is down (it's currently
  500ing).
- **YTS direct provider** (`PopcornKit/Sources/Managers/YTSApi.swift`).
  Mirrors Popcorn-Desktop 0.5.1's `butter-provider/yts.js`. Talks to
  `yts.lt` first, with `yts.am` and `yts.mx` as failover hosts (yts.mx
  now serves the website HTML rather than the API). Responses are
  remapped into popcorn-api's JSON shape and run through ObjectMapper,
  so they end up as ordinary `Movie` values that merge cleanly with the
  rest of the pipeline.
- **Dedicated torrent endpoints**: `getMovieTorrents(_:)` and
  `getEpisodeTorrents(showImdbId:season:episode:)` hit the
  `/movie/{id}/torrents` and `/show/{id}/{s}/{e}/torrents` endpoints
  Popcorn-Desktop uses (its `detail()` method intentionally returns
  `old_data`; only the dedicated endpoint refreshes torrents).
  `MovieDetailsViewModel.load` now keeps the catalogue metadata and
  unions fresh torrents into `self.movie.torrents` instead of
  overwriting with the metadata-only `/movie/{id}` response.
- **Forced tracker injection on every magnet**
  (`Torrent.augmentMagnetWithForcedTrackers`). Mirrors
  Popcorn-Desktop's `Settings.trackers.forced` exactly (13 trackers).
  Normalises `&amp;` HTML-encoding (uxert.link returns it that way),
  parses existing `tr=` params, dedups by host:port, appends only what's
  missing. Brings peer discovery in line with the desktop client even
  on torrents whose .torrent file only carried 1–3 locale-specific
  trackers.
- **Vendored PopcornTorrent** in `Packages/PopcornTorrent/` with
  `popcorntorrent.patch` riding on top. Streaming pre-buffer
  (`MIN_PIECES`) cut from "3% of file or up to 20 pieces ≈ 80 MB" to
  `[4, 6]` pieces (≈ 8–24 MB) so first-frame latency matches the
  desktop client. Project switched from a remote SwiftPM dep to an
  `XCLocalSwiftPackageReference`.
- **CrashReporter** in `App.swift` catches `NSUncaughtException` and
  POSIX signals (`SIGABRT`/`SIGSEGV`/`SIGBUS`/`SIGILL`/`SIGTRAP`/
  `SIGFPE`/`SIGPIPE`), dumps a timestamped stack trace via
  async-signal-safe `write(2)` to `~/Library/Application
  Support/PopcornTime/crashes/`, then re-raises the default handler so
  the OS still produces its own `.ips` report. On the next launch the
  log is logged via `os.log` (subsystem `swiftui.PopcornTime`) and dumped
  to stderr, then archived under `crashes/seen/`.
- Top-level `Makefile` with one-line targets for build, run, compare,
  clean, and the same matrix CI runs.
- `make build-original` worktree-builds the upstream commit (`835198f`)
  into `./build/original/` for visual diffing.
- `make refresh-popcorntorrent` re-pulls `alextud/PopcornTorrent@v2_3`
  and reapplies `popcorntorrent.patch` for manual upstream syncs.
- `.github/dependabot.yml` weekly updates for Swift Package Manager and
  GitHub Actions.
- Modern issue forms (`.github/ISSUE_TEMPLATE/*.yml`) and a pull-request
  template.
- `.swiftformat`, `.editorconfig`, and `.gitattributes` to standardise
  formatting and line endings.
- iOS 26 Liquid Glass on the player playback buttons, the player bottom
  toolbar, the trailer close button, and the macOS `VisualEffectBlur`.
  `MovieDetailsView` and `ShowDetailsView` action rows are wrapped in
  `GlassEffectContainer` so the buttons morph as a group.
- Universal `arm64 + x86_64` macOS `.app` artifact released on tag.

### Changed
- Deployment targets bumped to **tvOS 26 · iOS 26 · macOS 26**.
- swift-tools-version bumped to **6.2**, Swift language mode to **6**.
- `Package.resolved` written in v3 schema.
- **`Movie.init` reads every locale**, not just `torrents.en`. Many
  titles ship only under non-English buckets (Apex 2026 returns a
  populated `torrents.ua` and an empty `torrents.en` on uxert.link),
  which previously made them appear in search but trip "no torrents
  found" on play. Movie now unions every locale, dedupes by URL, and
  keeps the highest seed count.
- **`parseTorrentsResponse` accepts every shape live mirrors return**:
  flat array of payloads, locale-keyed → quality-keyed dict, or flat
  quality-keyed dict. Previous parser only accepted the dict shapes.
- popcorn-api requests now send `showAll=1` and `limit=50` (matches
  Popcorn-Desktop 0.5.1).
- `SecondaryScreen` rewritten on `UIScene.willConnectNotification` /
  `didDisconnectNotification` (replaces the deprecated
  `UIScreen.didConnect/didDisconnectNotification`).
- `VLCMediaPlayer.resetEqualizer` / `equalizerEnabled` replaced with the
  new `VLCAudioEqualizer` property.
- `AVAssetImageGenerator.copyCGImage(at:actualTime:)` replaced with the
  async `image(at:)` API.
- `UIScreen.screens` traversal replaced with
  `UIApplication.shared.connectedScenes` filtering.
- CI workflow consolidated from three duplicated jobs into a single
  matrix; `xcbeautify` formats logs; `ldid` is cached between runs.
- `VLCKit/get-vlc-frameworks.sh` hardened (`set -euo pipefail`,
  `curl -fsSL --retry 3`, fail-fast on missing extracted directory).
- Forced-tracker list updated to match Popcorn-Desktop's
  `Settings.trackers.forced` byte-for-byte (was missing `tracker.bittor.pw`,
  `tr4ck3r.duckdns.org`, `tracker.therarbg.to`; had wrong port on
  `tracker.openbittorrent.com`).

### Fixed
- Crash on torrent quality select (`EXC_BREAKPOINT` in
  `swift_task_isCurrentExecutorWithFlagsImpl`): the closure passed to
  `PTTorrentStreamer`'s `selectFileToStream:` is now declared
  `@Sendable` and forwards to a `nonisolated` method, so libtorrent's
  background `com.popcorntimetv.popcorntorrent.alerts` queue can call it
  without tripping the main-actor executor check.
- Crash on player setup (`MPMediaItemArtwork.jpegData(with:)` →
  `_swift_task_checkIsolatedSwift` trap): the artwork request handler
  closure is now `@Sendable` so MediaPlayer can invoke it from its
  background dispatch queue.
- iOS Info.plist `armv7` capability replaced with `arm64`.
- All actionable Swift 6 strict-concurrency warnings cleared.

### Removed
- **Build-time dependency on `alextud/PopcornTorrent`'s GitHub repo.**
  PopcornTorrent is now committed at `Packages/PopcornTorrent/` (≈180 MB,
  ≈177 MB of which is boost headers needed by libtorrent at compile time).
  Repo `.git` size with pack compression is ≈33 MB. Disposable upstream
  subtrees were dropped: `PopcornTorrentTests/`, `Package.resolved`,
  `update_boost.sh`, `update_torrent.sh`.
- Redundant `if #available(iOS 16, *)` guards now that iOS 26 is the
  minimum.
- Deprecated `Text + Text` concatenation, replaced with string
  interpolation.
- Legacy `ISSUE_TEMPLATE.md` (root) and `.github/ISSUE_TEMPLATE/bug_report.md`
  in favour of the YAML form templates.

### Notes
- **Dependency posture.** Live upstreams (VLCKit, Kingfisher, SwiftyJSON,
  ObjectMapper, GCDWebServer, plus the Trakt/TMDB/OpenSubtitles/Fanart/
  Popcorn/DHT/YTS HTTP services) are fetched on demand. PopcornTorrent
  is in-tree because its upstream branch is frozen and our patch needs
  to ride on top either way. See `make refresh-popcorntorrent` if a
  useful upstream change ever does land.

## Pre-modernization (upstream)

See `git log 835198f` for the upstream history before this fork's
modernization began.
