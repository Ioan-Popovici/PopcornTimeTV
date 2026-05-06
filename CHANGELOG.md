# Changelog

All notable changes are recorded here. Dates are ISO-8601. The
project adopts [Semantic Versioning](https://semver.org/) and the
[Gitflow](https://git-flow.sh/workflows/gitflow) branching model
(`master` for tagged releases, `develop` for integration).

## Unreleased

## [4.2.0] — 2026-05-07

### Added
- **"Low" auto-select quality**. Settings → Auto Select Quality now
  has an honestly-named `Low` option (always picks the lowest available
  resolution, useful on slow or metered connections). Replaces the
  misleading `Normal` label that did the same thing. Existing users on
  `Normal` are mapped to `Low` on read, so no setting is lost.
- **Cache survives player exit**. Closing the player no longer wipes
  the on-disk torrent cache. The "Clear Cache Upon Exit" toggle now
  fires on **app exit** instead — `scenePhase .background` for the
  iOS/tvOS/standard macOS path plus `applicationWillTerminate` in the
  macOS `AppDelegate` for the Cmd-Q route. Re-watching the same movie
  picks up from on-disk pieces; seek-back across sessions is instant.
- **`MoviePrefetcher` infrastructure** in
  `PreloadTorrentViewModel.swift`. Defines a singleton background
  warmer that picks the auto-quality target the moment the user lands
  on a movie detail page so by the time they tap Play the magnet is
  already past metadata + initial peer discovery. **Currently
  disabled at the call site** — rapid `start/cancel` cycles (target
  shifts as torrents merge in across multiple async fetch calls)
  triggered libtorrent peer-connection use-after-free in
  `peer_connection::on_receive_data`. Safe re-enablement requires
  isolating the prefetch on its own libtorrent session so cancel
  can't race with in-flight peer I/O on a torrent the play streamer
  cares about. The class stays in-tree alongside the disabled
  `TorrentSessionWarmer.warmAllRecentlyPlayed` (App.swift) for the
  same future re-architecture.

### Changed
- **`bufferingProgress` is now monotonic** for external consumers.
  `PTTorrentStreamer.pieceFinishedAlert` was reporting the
  *current sliding-piece-window* completion ratio
  (`1.0 − missing/total`); after the first window completed,
  `prioritizeNextPieces` cleared and refilled the window with the
  next batch and the next callback computed `1.0 − 3/4 = 0.25`,
  making the preload bar lurch 100 → 25 → 100 % as windows slid. A
  new `_initialBufferingComplete` ivar latches on the first
  `allRequiredPiecesDownloaded == YES` and pins the public value at
  `1.0` thereafter; the windowed maths stay internal for fast-
  forward seek tracking.
- **Seek priority preservation**. `prioritizeNextPieces` no longer
  blasts every piece's priority back to `low_priority` and clears
  every deadline on each window slide — that was killing in-flight
  prefetch from prior seeks (peers stop sending a piece the moment
  its priority drops + deadline clears). The new selective demote
  only knocks the *previously top-prioritised* `required_pieces`
  back down; everything else keeps whatever priority it had. Net
  effect: pieces that were 80 % done from a previous seek-back
  finish naturally on idle bandwidth, the movie genuinely
  accumulates on disk, and seek-back to a watched region is
  instant instead of triggering a fresh fetch.
- **Adaptive seconds-of-runtime pre-buffer gate dropped.** The
  Swift-side `evaluateAdaptiveGate` used to hold playback for
  Balanced=4 s / Smooth=8 s of decoded runtime *after*
  `readyToPlay` had already fired, as insurance against mid-
  playback speed dips. With the seek-priority fix making
  intermediate pieces actually accumulate AND VLC's own
  `.buffering` covering transient hiccups AND
  `PlaybackHealthMonitor` catching chronic swarm collapses, that
  insurance was redundant — and confusing ("buffering at 100 %?").
  Now `readyToPlay` means play immediately. `Fast/Balanced/Smooth`
  presets are now purely *how many head pieces libtorrent waits
  for*: 3 / 4 / 8 — honest about what they control.
- **Preload UI is now Apple HIG-compliant**.
  `PreloadTorrentView`'s indeterminate-bouncing `ProgressView()` +
  separate "Buffered: X%" determinate text label (HIG: don't mix
  determinate text with indeterminate bar) replaced with a single
  determinate `ProgressView(value: viewModel.progress)` bound to
  the now-monotonic `bufferingProgress`. The stats panel's
  "Buffered" row renamed to "Downloaded" and bound to
  `totalProgress` — honest "how much of the file is on disk".
- **Settings copy reflects current behaviour**. Buffering Strategy
  descriptions now describe head-piece counts honestly (no longer
  promise "a few seconds of headroom" — that gate is gone).
  Auto-Select Quality picker reordered with `Low` in place of
  `Normal`; Optimal description rewritten to remove the
  "waits for enough buffer to play without stuttering" line that no
  longer applies.

### Fixed
- **Bar oscillation 100 → 25 → 100 % during pre-buffer**. See the
  `bufferingProgress` monotonic latch above.
- **Seek-back losing in-progress prefetch**. See the selective
  demote in `prioritizeNextPieces` above. Symptom users hit:
  rapid forward + back jumps caused libtorrent to thrash, with
  partial pieces from the prior target never finishing.
- **`SettingsView` spinner inconsistency**. Dropped the explicit
  `CircularProgressViewStyle(tint: .blue)` / `…Style()` calls in
  the OpenSubtitles login flow — `ProgressView()`'s default style
  adapts per platform and matches the rest of the app.
- **Dead `rateRatio` config + `waitingForRate` enum case**. All
  three `PrebufferPolicy` presets had `rateRatio: nil`, so the
  rate gate never fired; struck along with the unreachable
  `waitingForRate` status case + its localisation strings + the
  helper machinery (`fileBitrate`, `parseSize`, `torrentSizeBytes`,
  `avgDownloadSpeed`) that only fed it.

## [4.1.0] — 2026-05-05

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
- **Auto-quality rename + Selectable mode.** `Best/Better/Good/Auto`
  replaced with `Optimal/Highest/Normal/Selectable`. `Selectable` opens
  the torrent picker every play instead of auto-resolving — useful when
  the auto-pick keeps landing on a stale source.
- **Buffering Strategy setting** (Settings → Playback → `Fast` /
  `Balanced` / `Smooth`). Plumbed through to libtorrent via a new
  `+[PTTorrentStreamer setMinPiecesOverride:]` class method, so the
  byte-level pre-buffer floor actually moves with the user choice
  (Fast ≈ 3 head pieces, Balanced ≈ 4, Smooth ≈ 8) instead of being
  hardcoded at 4–6. Pairs with the Swift adaptive gate (Fast bypasses
  the `targetSeconds` headroom check; Balanced waits 4 s; Smooth 8 s).
- **Audio Language picker** in Settings. Drives both torrent selection
  (prefers releases that include the requested track) and a one-shot
  VLC track switch on play, so a Russian-language preference lands on
  the dual-audio source *and* swaps to the right track without manual
  intervention. Picker also infers multi-track from Russian-scene
  release markers (`Дубляж`, `LostFilm`, `MVO`, etc.) when the torrent
  metadata doesn't list audio tracks explicitly.
- **Source-quality torrent ranking + collapsed picker.** Torrents are
  bucketed by quality (`1080p`, `720p`, `480p`, `3D`) and the best
  source per bucket leads the picker; remaining sources collapse under
  a "Show all sources…" disclosure so the picker doesn't drown in
  dozens of mirror copies. Ranking uses seed count + provider trust +
  release-tag hints (e.g. `WEB-DL` over `HDTS`).
- **Per-platform Settings UI.** Each platform body
  (`iOSBody`/`tvOSBody`/`macOSBody`) renders shared `@ViewBuilder`
  rows in its native idiom — `insetGrouped` list (iOS), Apple-Music-
  style SF-Symbol button rows with detail screens (tvOS), grouped
  `Form` with inline `Picker(.menu)` and dynamic footer copy (macOS).
- **Picker-based Switch source.** Long-press Play (or "Switch source"
  during preload) re-opens the torrent picker pre-launch instead of
  silently jumping to the next-best torrent — the user picks the
  replacement.
- **Preload screen carries through first-frame handoff.** The blurred-
  backdrop + spinner stays mounted on top of the freshly-mounted
  `PlayerView` until VLC actually renders the first frame
  (`mediaPlayerTimeChanged` flips `isLoading` false), eliminating the
  1–3 s black gap on Fast strategy where libtorrent has handed VLC
  the bytes but VLC is still parsing the container. Implemented via
  `PlayingWithPreloadCover` — a wrapper that holds the player model
  as `@ObservedObject` so SwiftUI re-renders on the flip.
- **`PlaybackHealthMonitor`** surfaces stall reasons during pre-buffer
  (`slowStart`, `peerCollapse`, `sustainedLowSpeed`, `bufferStall`)
  and feeds the inline "Switch source" prompt copy. Mid-playback the
  monitor still runs but doesn't surface (one UI). 30-day
  `PlaybackFailureRegistry` (UserDefaults-backed) blacklists
  consistently-failing magnets so auto-pick avoids them.
- **Adaptive pre-buffer with friendly status text.** `PrebufferPolicy`
  encodes `targetSeconds` / `maxWaitSeconds` per strategy, evaluated
  against bytes-buffered + media duration. Status line on the preload
  screen shifts from "Connecting to source…" → "Downloading…" once
  bytes are flowing.
- **Early `GCDWebServer` start.** Server now starts in
  `metadataReceivedAlert` (the moment libtorrent has the torrent
  metadata) instead of waiting for `allRequiredPiecesDownloaded`.
  The HTTP `GET` handler queues VLC's raw `GCDWebServerRequest` and
  builds the file response only once `pieceFinishedAlert` confirms
  the requested byte range is on disk — `GCDWebServerFileResponse
  initWithFile:byteRange:` aborts (rather than nil-returning) when
  the file is missing, which is why we queue the request and
  construct the response lazily.
- **API Endpoints settings**
  (`PopcornKit/Sources/Managers/APIEndpoints.swift`). UserDefaults-
  backed override for 7 public services (Trakt, TMDB, Fanart,
  OpenSubtitles, OMDb, YTS, DHT). Edit each URL in Settings → API
  Endpoints; resolved at first access of `<Service>.base`, so
  changes apply on next launch. "Reset all to defaults" clears every
  override.
- **Popcorn API server list UI.** Replaces the single comma-separated
  TextField with a System-Settings-style list: rows with inline
  `−` (or swipe-to-delete on iOS), an "add server" row at the bottom,
  and a "Restore Defaults" action. Persistence flows through
  `PopcornKit.setUserCustomUrls(_:)` so the live mirror-checker still
  validates the new list.
- **`Streaming details` Settings toggle.** When off the preload screen
  drops the bar + stats panel and shows just a centered indeterminate
  spinner — quieter loading UI for users who don't want the technical
  readout.
- **Recently-played magnet LRU + `TorrentSessionWarmer`.** Records
  successful `readyToPlay` magnets per-user so the next launch can
  warm those torrent sessions ahead of time. Currently disabled at
  the call sites (warmup → play handoff still has piece-priority
  contention bugs); kept compiled for follow-up.

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
- **libtorrent session tuning.** Fixed DHT bootstrap typo + added two
  more bootstrap nodes; added the `ut_pex` plugin; set
  `peer_connect_timeout: 5` and `handshake_timeout: 10`;
  `announce_to_all_trackers/tiers: true` so all trackers hit in
  parallel rather than serially. UPnP / NAT-PMP and connection
  encryption stay off — both correlated with `auto_manage_torrents
  → is_inactive` SEGVs.
- **`MIN_PIECES` now driven by user choice.** Default clamp is still
  4–6 (auto-computed from 0.5 % of file size); `+setMinPiecesOverride:`
  lets `PreloadTorrentViewModel.playTorrent()` push the
  `Buffering Strategy` value (3 / 4 / 8) before each play.
- **`OpenSubtitlesHash.hashFor` rewritten on the modern throwing
  `FileHandle` API.** `guard let` instead of force-unwrap; per-call
  `do/catch`; validates each read returned a full chunk; uses
  `Data.withUnsafeBytes { … bindMemory(to: UInt64.self) }` instead of
  `NSData.bytes.assumingMemoryBound`. Returns an empty hash on any
  I/O error so subtitle search falls back to imdb / episode matching.
- **`PopcornKit.serverURL()`** falls back to
  `Popcorn.fallbackMirrors.joined(",")` when `Session.popcornBaseUrls`
  is empty, so the Settings field reflects what the app is actually
  using rather than reading blank.
- `Popcorn.fallbackMirrors` made `public` so the Settings UI can
  pull the bundled defaults for the "Restore Defaults" action.

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
- **`SIGTRAP` in `OpenSubtitlesHash.hashFor`** when early-server-start
  handed `PlayerSubtitleModel` a sparse / not-yet-created file. Force
  unwrap of `FileHandle(forReadingAtPath: path)!` trapped on missing
  file; the rewrite (see Changed) tolerates both missing and short
  files.
- **`100 % buffered, no playback` after preload-as-cover handoff.**
  The `.preload → .play` state transition was re-mounting
  `PreloadTorrentView`, whose `.onAppear` fired `playTorrent()` a
  second time and created a *new* `PTTorrentStreamer` that orphaned
  the already-bound `playerModel`. `playTorrent()` is now idempotent
  (`guard playerModel == nil else { return }`).
- **Preload cover never dismissed despite VLC playing audio.** The
  `playerModel.isLoading` check inside the parent switch wasn't
  observed (captured enum payload). Extracted into
  `PlayingWithPreloadCover` which holds `playerModel` as
  `@ObservedObject` so SwiftUI re-renders on the flip.
- **VLC black-screen on first play with `drawable size = 0×0`**
  (VLCKit issue 25264). `fixFirstTimeInvalidSize(view:)` workaround
  re-enabled in `VLCPlayerView`.
- **`SEGV` in `auto_manage_torrents → is_inactive`** when UPnP +
  encryption were enabled together. Both reverted off.
- **`std::sort` crash in `request_time_critical_pieces`** caused by
  aggressive `connection_speed=100` + `max_failcount=1` libtorrent
  tuning (high peer churn). Reverted to libtorrent defaults.
- **`SIGTRAP` in `TorrentSessionWarmer.selectFileToStream`** —
  `@MainActor` closure was invoked from libtorrent's background
  alerts queue. Closure now declared `@Sendable`.
- **"Playback unstable" surfacing during stable playback.** The
  `peerCollapse` health signal was firing on momentary peer dips
  *after* playback started; now gated to `phase == .preBuffer` only.
- **"Source is slow to start" surfacing after playback began.** A
  pre-buffer `slowStart` issue carried over into `PlayerView`'s
  observation; `PlaybackHealthMonitor.resetForPlayback()` clears
  stale issues on handoff.
- **Clear Cache hang** caused by walking all of `NSTemporaryDirectory`
  recursively. Scoped to `<temp>/Downloads/` and stripped the
  per-folder size accounting that triggered the walk.
- **Subtitle preferred-language warning false-positives.** `match` is
  now compared case-insensitively and surfaces `missingPreferredSubtitle
  Language` only when no candidates exist for the configured language
  *and* fallback locales.

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
