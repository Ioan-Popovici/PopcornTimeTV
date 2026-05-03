# Changelog

All notable changes are recorded here. Dates are ISO-8601.

## Unreleased — 2026-05

### Added
- Top-level `Makefile` with one-line targets for build, run, compare,
  clean, and the same matrix CI runs.
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

### Fixed
- Crash on torrent quality select (`EXC_BREAKPOINT` in
  `swift_task_isCurrentExecutorWithFlagsImpl`): the closure passed to
  `PTTorrentStreamer`'s `selectFileToStream:` is now declared
  `@Sendable` and forwards to a `nonisolated` method, so libtorrent's
  background `com.popcorntimetv.popcorntorrent.alerts` queue can call it
  without tripping the main-actor executor check.
- iOS Info.plist `armv7` capability replaced with `arm64`.
- All actionable Swift 6 strict-concurrency warnings cleared.

### Removed
- Redundant `if #available(iOS 16, *)` guards now that iOS 26 is the
  minimum.
- Deprecated `Text + Text` concatenation, replaced with string
  interpolation.
- Legacy `ISSUE_TEMPLATE.md` (root) and `.github/ISSUE_TEMPLATE/bug_report.md`
  in favour of the YAML form templates.

## Pre-modernization (upstream)

See `git log 835198f` for the upstream history before this fork's
modernization began.
