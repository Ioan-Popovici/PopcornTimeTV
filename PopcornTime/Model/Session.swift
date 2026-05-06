//
//  Session.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation
import PopcornTorrent

private extension UserDefaults {
    func optionalString(forKey key: String) -> String? { string(forKey: key) }
    func optionalData(forKey key: String) -> Data? { data(forKey: key) }
    func optionalDate(forKey key: String) -> Date? { object(forKey: key) as? Date }
}

enum Session {
    static var tosAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: "tosAccepted") }
        set { UserDefaults.standard.set(newValue, forKey: "tosAccepted") }
    }

    /// One of `"Optimal"`, `"Highest"`, `"Low"`, `"Selectable"`.
    /// Defaults to `"Optimal"` for new installs and on upgrade from
    /// versions where this stored `nil` (which used to mean "show the
    /// picker every time"). Optimal auto-plays the highest-`qualityScore`
    /// source — see `SelectTorrentQualityButton.autoSelectTorrent`.
    ///
    /// Legacy values stored by older builds (`"Best"`, `"Lowest"`,
    /// `"Off"`, `"Normal"`) are mapped to the current names on read so
    /// existing users don't lose their setting. `"Normal"` was the
    /// pre-rename label for what is now `"Low"` (lowest available
    /// resolution) — the rename is just an honest label, the
    /// behaviour is unchanged.
    static var autoSelectQuality: String {
        get {
            let stored = UserDefaults.standard.optionalString(forKey: "autoSelectQuality") ?? "Optimal"
            switch stored {
            case "Best":   return "Optimal"
            case "Lowest": return "Low"
            case "Normal": return "Low"
            case "Off":    return "Selectable"
            default:       return stored
            }
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoSelectQuality") }
    }

    /// Preferred audio language for torrent selection (ISO 639-1, e.g. "en",
    /// "ru", "ua"). Defaults to **English** for first-run users; if a title
    /// has no English audio, `selectableTorrents` falls back to whatever
    /// language the movie does have (and `LanguageSelector` surfaces that
    /// actual language in its label). Set to "" to disable preference and
    /// treat every locale equally.
    static var preferredAudioLanguage: String {
        get {
            if let stored = UserDefaults.standard.optionalString(forKey: "preferredAudioLanguage") {
                return stored
            }
            return "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferredAudioLanguage")
        }
    }

    static var streamOnCellular: Bool {
        get { UserDefaults.standard.bool(forKey: "streamOnCellular") }
        set { UserDefaults.standard.set(newValue, forKey: "streamOnCellular") }
    }

    /// `true` (default) → preload screen shows the full chrome:
    /// progress bar, status text, and a Buffered/Download/Peers stats
    /// panel. `false` → minimal loading screen with just an
    /// indeterminate spinner and the title. Useful when the user
    /// finds the technical details noisy and just wants a clean
    /// "loading" indicator while they wait.
    static var showStreamingDetails: Bool {
        get { UserDefaults.standard.object(forKey: "showStreamingDetails") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showStreamingDetails") }
    }

    /// Pre-buffer strategy — controls how many head pieces libtorrent
    /// must have on disk before `readyToPlay` fires. One of `"Fast"`
    /// (3 head pieces — default, snappiest start), `"Balanced"` (4
    /// head pieces — works on most swarms), or `"Smooth"` (8 head
    /// pieces — more upfront wait, more cushion on slow connections).
    static var bufferingStrategy: String {
        get { UserDefaults.standard.optionalString(forKey: "bufferingStrategy") ?? "Fast" }
        set { UserDefaults.standard.set(newValue, forKey: "bufferingStrategy") }
    }

    static var removeCacheOnPlayerExit: Bool {
        get { UserDefaults.standard.bool(forKey: "removeCacheOnPlayerExit") }
        set { UserDefaults.standard.set(newValue, forKey: "removeCacheOnPlayerExit") }
    }

    /// `true` (default) → tapping Play on a movie/episode with saved
    /// progress jumps straight to the saved position. `false` → playback
    /// starts from the beginning. There's no in-player prompt either
    /// way (the legacy "Resume Playing / Start from Beginning" alert
    /// has been removed); this setting is the single control. The
    /// PlayButton's "Resume" label still flips whenever progress
    /// exists — the label says "you have saved progress", the toggle
    /// says "do I auto-jump on tap".
    static var autoResume: Bool {
        get { UserDefaults.standard.object(forKey: "autoResume") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoResume") }
    }

    static var themeSongVolume: Float {
        get {
            let raw = UserDefaults.standard.object(forKey: "themeSongVolume") as? Float
            return raw ?? 0.75
        }
        set { UserDefaults.standard.set(newValue, forKey: "themeSongVolume") }
    }

    static var oauthCredentials: Data? {
        get { UserDefaults.standard.optionalData(forKey: "oauthCredentials") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "oauthCredentials") }
            else { UserDefaults.standard.removeObject(forKey: "oauthCredentials") }
        }
    }

    static var skipReleaseVersion: Data? {
        get { UserDefaults.standard.optionalData(forKey: "skipReleaseVersion") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "skipReleaseVersion") }
            else { UserDefaults.standard.removeObject(forKey: "skipReleaseVersion") }
        }
    }

    static var subtitleSettings: Data? {
        get { UserDefaults.standard.optionalData(forKey: "subtitleSettings") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "subtitleSettings") }
            else { UserDefaults.standard.removeObject(forKey: "subtitleSettings") }
        }
    }

    static var lastVersionCheckPerformedOnDate: Date? {
        get { UserDefaults.standard.optionalDate(forKey: "lastVersionCheckPerformedOnDate") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "lastVersionCheckPerformedOnDate") }
            else { UserDefaults.standard.removeObject(forKey: "lastVersionCheckPerformedOnDate") }
        }
    }

    /// Magnets the user has successfully started playing recently, in
    /// LRU order (most recent first). At app launch
    /// `TorrentSessionWarmer` re-attaches each one to libtorrent's
    /// session so the metadata + peer cache survives across launches —
    /// re-watching the same movie skips the cold magnet→metadata fetch
    /// that's the dominant chunk of "Connecting to source…" wait time.
    /// Mirrors popcorn-desktop's `initExistTorrents` (their
    /// `tmpLocation/TorrentCache/` directory of stored magnets).
    static var recentlyPlayedMagnets: [String] {
        get { UserDefaults.standard.stringArray(forKey: "recentlyPlayedMagnets") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "recentlyPlayedMagnets") }
    }

    /// Push `magnetURL` to the front of the recently-played LRU and
    /// trim to 20. Safe to call on duplicates — existing entries are
    /// removed first so the most-recent timestamp wins.
    static func recordRecentlyPlayed(magnetURL: String) {
        guard !magnetURL.isEmpty else { return }
        var list = recentlyPlayedMagnets
        list.removeAll { $0 == magnetURL }
        list.insert(magnetURL, at: 0)
        recentlyPlayedMagnets = Array(list.prefix(20))
    }
}

#if os(macOS)
// MARK: - Storage path overrides (macOS, sandboxed)

/// User-overridable streaming-cache and saved-downloads roots. macOS
/// only because the app is sandboxed there: arbitrary file paths need
/// security-scoped bookmarks (`com.apple.security.files.user-selected.
/// read-write` + `bookmarks.app-scope` entitlements) so the granted
/// access survives across launches. iOS / tvOS keep the platform default
/// paths under their own sandboxes — the user can't browse to anything
/// else anyway.
extension Session {
    private static let streamingCacheBookmarkKey = "streamingCacheBookmark"
    private static let savedDownloadsBookmarkKey = "savedDownloadsBookmark"

    // `nonisolated(unsafe)` because Swift 6 strict concurrency rightly
    // flags static mutable state, but in practice these are only ever
    // written from the main actor — Settings UI handlers and `App.init`
    // — and read on the same actor afterwards. No background access.
    nonisolated(unsafe) private static var resolvedStreamingCacheURL: URL?
    nonisolated(unsafe) private static var resolvedSavedDownloadsURL: URL?

    /// Effective streaming-cache path — the override if one is active,
    /// otherwise PTTorrentStreamer's `NSTemporaryDirectory()/Downloads`
    /// default. Settings reads this for display.
    static var streamingCachePath: String {
        if let url = resolvedStreamingCacheURL { return url.path }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent("Downloads")
    }

    /// Effective saved-downloads path. Default mirrors
    /// `+[PTTorrentDownload downloadDirectory]` (Documents/Downloads on
    /// macOS).
    static var savedDownloadsPath: String {
        if let url = resolvedSavedDownloadsURL { return url.path }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last
        return docs?.appendingPathComponent("Downloads").path ?? ""
    }

    static var hasStreamingCacheOverride: Bool { resolvedStreamingCacheURL != nil }
    static var hasSavedDownloadsOverride: Bool { resolvedSavedDownloadsURL != nil }

    /// Persist the user's streaming-cache choice and push it into
    /// PTTorrentStreamer. Pass `nil` to clear and revert to the default.
    static func setStreamingCachePath(_ url: URL?) {
        applyStorageOverride(url: url,
                             bookmarkKey: streamingCacheBookmarkKey,
                             apply: { PTTorrentStreamer.setDownloadDirectoryOverride($0) },
                             store: { resolvedStreamingCacheURL = $0 })
    }

    /// Persist the user's saved-downloads choice and push it into
    /// PTTorrentDownload. Pass `nil` to clear.
    static func setSavedDownloadsPath(_ url: URL?) {
        applyStorageOverride(url: url,
                             bookmarkKey: savedDownloadsBookmarkKey,
                             apply: { PTTorrentDownload.setDownloadDirectoryOverride($0) },
                             store: { resolvedSavedDownloadsURL = $0 })
    }

    /// Resolve persisted security-scoped bookmarks at app launch and
    /// apply them to the PT classes BEFORE any streamer is created.
    /// Stale or unresolvable bookmarks are silently dropped so the user
    /// just sees the default paths and can re-pick from Settings.
    static func applyStorageOverrides() {
        if let url = resolveBookmark(forKey: streamingCacheBookmarkKey) {
            resolvedStreamingCacheURL = url
            PTTorrentStreamer.setDownloadDirectoryOverride(url.path)
        }
        if let url = resolveBookmark(forKey: savedDownloadsBookmarkKey) {
            resolvedSavedDownloadsURL = url
            PTTorrentDownload.setDownloadDirectoryOverride(url.path)
        }
    }

    private static func applyStorageOverride(
        url: URL?,
        bookmarkKey: String,
        apply: (String?) -> Void,
        store: (URL?) -> Void
    ) {
        guard let url else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            apply(nil)
            store(nil)
            return
        }
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            _ = url.startAccessingSecurityScopedResource()
            apply(url.path)
            store(url)
        } catch {
            // Bookmark creation failed — most commonly because the user
            // picked a path the sandbox can't grant (e.g. /System).
            // Leave the previous override in place rather than wiping it.
            print("PopcornTime: bookmark creation failed for \(url.path): \(error)")
        }
    }

    private static func resolveBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.optionalData(forKey: key) else {
            return nil
        }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                // Folder moved / renamed since the bookmark was created.
                // Sandboxed apps can't refresh a stale bookmark
                // unilaterally — we'd need the user to re-grant access.
                UserDefaults.standard.removeObject(forKey: key)
                return nil
            }
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }
}
#endif

/// Holds long-running `PTTorrentStreamer` instances keyed by magnet
/// URL, used purely to keep libtorrent's session warm for likely-
/// played torrents. Two scenarios:
///
/// 1. **App launch restore** — at startup, every URL in
///    `Session.recentlyPlayedMagnets` is `warm()`-ed in the background.
///    Re-watching a movie a few hours later then skips the cold
///    magnet→metadata phase (libtorrent's session already has the
///    torrent_handle, peer connections, and chunks on disk).
///
/// 2. **Next-episode prefetch** — during episode playback, when the
///    UpNext overlay appears (i.e. < ~30s left in current episode),
///    `TorrentPlayerView` warms the next episode's auto-pick torrent.
///    This is the same pattern popcorn-desktop uses (their
///    `preloadNextEpisodeTime` setting + `stream:start ... 'preload'`).
///
/// **Critical invariant**: there can only be ONE `PTTorrentStreamer`
/// attached to a given magnet at a time. libtorrent's shared session
/// dedups torrents by infohash, and a play streamer added to a magnet
/// already held by a warm streamer ends up sharing the same
/// `torrent_handle` — when one cancels, the other's handle is
/// invalidated mid-stream and crashes VLC's read. Always
/// `release(magnetURL:)` BEFORE creating a play streamer for that
/// magnet. The on-disk pieces are kept (`deleteData: false`) so the
/// play streamer still benefits from the prefetch's work.
@MainActor
final class TorrentSessionWarmer {
    static let shared = TorrentSessionWarmer()

    private var warmStreamers: [String: PTTorrentStreamer] = [:]

    private init() {}

    /// Start a no-op streamer for `magnetURL` if not already warm.
    /// Idempotent — a second call with the same magnet is a no-op.
    func warm(magnetURL: String) {
        guard !magnetURL.isEmpty else { return }
        guard warmStreamers[magnetURL] == nil else { return }
        let s = PTTorrentStreamer()
        warmStreamers[magnetURL] = s
        // `selectFileToStream` is invoked synchronously from libtorrent's
        // alerts thread (`com.popcorntimetv.popcorntorrent.alerts`),
        // before any data has been downloaded — there's nowhere to
        // hop to MainActor without blocking it. Mark the closure
        // `@Sendable` so it's non-isolated; otherwise Swift's strict
        // concurrency check trips a `_swift_task_checkIsolatedSwift`
        // crash the moment metadata arrives.
        let selector: @Sendable ([String], [NSNumber]) -> Int32 = { _, fileSizes in
            guard fileSizes.count > 1 else { return 0 }
            var maxSize: Int64 = 0
            var maxIndex: Int32 = 0
            for (i, sz) in fileSizes.enumerated() {
                if sz.int64Value > maxSize {
                    maxSize = sz.int64Value
                    maxIndex = Int32(i)
                }
            }
            return maxIndex
        }
        s.startStreaming(
            fromMultiTorrentFileOrMagnetLink: magnetURL,
            progress: { _ in },
            readyToPlay: { _, _ in },
            failure: { _ in },
            selectFileToStream: selector
        )
    }

    /// Stop the warm streamer for `magnetURL` if any. **Must** be called
    /// before a play streamer is created for the same magnet — see the
    /// "critical invariant" above. Cached pieces are kept on disk.
    func release(magnetURL: String) {
        guard let s = warmStreamers.removeValue(forKey: magnetURL) else { return }
        s.cancelStreamingAndDeleteData(false)
    }

    /// Cancel every warm streamer and detach its torrent_handle from
    /// libtorrent's session. Called from `ClearCache.emptyCache()` so
    /// the next Play after a cache wipe doesn't dedup onto a stale
    /// handle pointing at a now-deleted save_path — that race aborts
    /// in GCDWebServer's file-response init when libtorrent reports
    /// "have piece" for bytes whose file no longer exists on disk.
    /// Cached pieces aren't kept (we're wiping them anyway).
    func releaseAll() {
        for s in warmStreamers.values {
            s.cancelStreamingAndDeleteData(false)
        }
        warmStreamers.removeAll()
    }

    /// Warm the most-recent magnets in `Session.recentlyPlayedMagnets`.
    /// Called once at app launch. We cap at 5 entries — restoring all
    /// 20 was floods the session: each warm streamer competes with the
    /// user's actual play streamer for tracker / DHT / peer slots, so
    /// "Connecting to source…" for a fresh pick paradoxically gets
    /// slower the more recently-played items we restore. Five gives a
    /// useful warm-up for actual re-watches without dragging
    /// new-source connect latency.
    func warmAllRecentlyPlayed() {
        for magnet in Session.recentlyPlayedMagnets.prefix(5) {
            warm(magnetURL: magnet)
        }
    }
}

/// Persists per-torrent playback-failure timestamps (stalls, peer drops,
/// slow starts) for the last 30 days so the picker can demote unreliable
/// sources. We don't blocklist — swarms recover, and a torrent that
/// stalled six weeks ago might be the best option today.
@MainActor
final class PlaybackFailureRegistry {
    static let shared = PlaybackFailureRegistry()

    private let key = "playbackFailureRegistry"
    private let retention: TimeInterval = 30 * 24 * 3600
    private var failures: [String: [Date]] = [:]

    private init() { load() }

    /// Record a failure for `url`. Idempotent within 60 seconds — rapid
    /// stall→stall transitions on the same source shouldn't compound.
    func recordFailure(url: String) {
        let now = Date()
        if let last = failures[url]?.last, now.timeIntervalSince(last) < 60 { return }
        failures[url, default: []].append(now)
        save()
    }

    /// Failure count for `url` within the retention window. Triggers a
    /// prune on access so the dictionary doesn't grow unbounded between
    /// app launches.
    func failureCount(url: String) -> Int {
        prune()
        return failures[url]?.count ?? 0
    }

    /// Score penalty to apply during quality ranking — subtracts from a
    /// `Torrent.qualityScore` so recent failures lose to clean
    /// alternatives without being permanently filtered out. Tuned so 1
    /// failure ≈ knocks a 1080p WEB-DL below a 720p BluRay; capped so a
    /// long failure history can't sink a torrent below screener tier.
    func qualityPenalty(url: String) -> Int {
        return min(failureCount(url: url) * 100, 1500)
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        for (url, dates) in failures {
            let kept = dates.filter { $0 >= cutoff }
            if kept.isEmpty {
                failures.removeValue(forKey: url)
            } else if kept.count != dates.count {
                failures[url] = kept
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [Date]].self, from: data) else {
            return
        }
        failures = decoded
        prune()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(failures) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
