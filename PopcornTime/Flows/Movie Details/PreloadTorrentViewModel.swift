//
//  PreloadTorrentViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 20.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation
import PopcornKit
import PopcornTorrent
import MediaPlayer.MPMediaItem
import Combine
import os
#if canImport(UIKit)
import UIKit
#endif

private let prefetchLog = Logger(subsystem: "swiftui.PopcornTime", category: "prefetch")

/// Warms up the auto-pick torrent in the background while the user
/// is still browsing the movie detail page. When they eventually tap
/// Play, the shared `PTTorrentsSession` already has the torrent's
/// metadata + initial peer set + first chunks cached, so the play
/// streamer's `readyToPlay` callback fires almost instantly instead
/// of waiting 5–15 seconds for cold magnet → metadata → peer
/// discovery.
///
/// Skipped for `Selectable` quality mode because we can't predict
/// which source the user will pick — prefetching the best-score one
/// would waste bandwidth in that case. For Optimal / Highest /
/// Normal, the auto-pick is deterministic and matches what
/// `SelectTorrentQualityButton.autoSelectTorrent` will return.
///
/// Lifecycle is per-`MovieDetailsView` (the prefetcher is owned by
/// `PlayButton` as a `@StateObject`). The streamer is cancelled when
/// the prefetcher is deinitialised, so the data we've pulled stays
/// in the temp cache and is reused if the user taps Play within the
/// same session.
/// Single global background warmer. Tying this to a per-`PlayButton`
/// `@StateObject` was unreliable: SwiftUI's `NavigationStack` doesn't
/// guarantee `.onDisappear` fires on push, and `@StateObject` deinit
/// timing depends on whether the parent retains the view. The
/// singleton sidesteps both: only one prefetch is ever active at a
/// time, and `start(media:)` for a new movie atomically cancels
/// whatever was warming before.
@MainActor
final class MoviePrefetcher {
    static let shared = MoviePrefetcher()

    /// `nonisolated(unsafe)` so the (implicitly nonisolated) deinit
    /// can release the streamer. `PTTorrentStreamer` isn't `Sendable`
    /// but is safe in practice — libtorrent's session does its own
    /// locking. All non-deinit reads/writes are main-actor via
    /// `start(media:)` and `cancel()`.
    nonisolated(unsafe) private var streamer: PTTorrentStreamer?
    nonisolated(unsafe) private var prefetchedURL: String?

    private init() {}

    /// Pick the torrent that `SelectTorrentQualityButton.autoSelect
    /// Torrent` would pick for the current `Session.autoSelectQuality`,
    /// and kick off a background streamer for it. Idempotent: a
    /// second call with the same target is a no-op while the first
    /// is in flight; switching to a different target cancels the
    /// previous.
    func start(media: Media) {
        // Don't prefetch when the user explicitly wants the picker —
        // we can't guess which source they'll choose, and prefetching
        // the wrong one wastes bandwidth.
        guard Session.autoSelectQuality != "Selectable" else {
            prefetchLog.info("skip — autoSelectQuality=Selectable for \(media.title, privacy: .public)")
            return
        }

        guard let target = autoPickTarget(in: media.torrents) else {
            prefetchLog.info("skip — no torrent picked (have \(media.torrents.count)) for \(media.title, privacy: .public)")
            return
        }
        guard prefetchedURL != target.url else {
            prefetchLog.info("already warming \(target.quality ?? "?", privacy: .public) for \(media.title, privacy: .public)")
            return
        }

        cancel()
        prefetchedURL = target.url
        prefetchLog.info("start \(target.quality ?? "?", privacy: .public) for \(media.title, privacy: .public)")

        let s = PTTorrentStreamer()
        self.streamer = s
        // All four streamer callbacks are invoked from libtorrent's
        // background `com.popcorntimetv.popcorntorrent.alerts` queue,
        // not from the main actor. Closures created inside this
        // `@MainActor` class would otherwise inherit @MainActor
        // isolation, and Swift 6 traps with SIGTRAP the first time
        // libtorrent fires the selectFileToStream block from off-
        // main (this killed the app while waiting on the movie
        // details page). `@Sendable` opts the closures out of the
        // isolation inheritance so they run on whatever thread
        // libtorrent calls them on.
        let progress: @Sendable (PTTorrentStatus) -> Void = { _ in }
        let ready: @Sendable (URL, URL) -> Void = { _, _ in }
        let failure: @Sendable (Error) -> Void = { _ in }
        let selector: @Sendable ([String], [NSNumber]) -> Int32 = { _, fileSizes in
            // Mirror PreloadTorrentViewModel's biggest-file pick so
            // the data we cache is the same one the play streamer
            // will need. For single-file torrents this is trivial.
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
            fromMultiTorrentFileOrMagnetLink: target.url,
            progress: progress,
            readyToPlay: ready,
            failure: failure,
            selectFileToStream: selector
        )
    }

    /// Tear down the prefetch streamer. Pass `false` to
    /// `cancelStreamingAndDeleteData` so the partial data on disk is
    /// kept — the play streamer can pick up from where prefetch left
    /// off if the user taps Play immediately.
    func cancel() {
        if let url = prefetchedURL {
            prefetchLog.info("cancel — was warming \(url, privacy: .public)")
        }
        streamer?.cancelStreamingAndDeleteData(false)
        streamer = nil
        prefetchedURL = nil
    }

    /// Mirror of `SelectTorrentQualityButton.autoSelectTorrent`'s
    /// switch on `Session.autoSelectQuality`. Kept here as a free
    /// function rather than reaching across to the view's helper
    /// because the view's `collapsedSelectableTorrents` filter is
    /// language/audio-aware and bound to its own `@State`. For
    /// prefetch purposes the un-collapsed pool gives the same
    /// `max`/`min`-by-score answer for Optimal and the same
    /// extremes for Highest/Low — and if it picks slightly
    /// differently, the worst case is wasted background bandwidth
    /// (the play streamer still serves the user's actual choice).
    private func autoPickTarget(in pool: [Torrent]) -> Torrent? {
        guard !pool.isEmpty else { return nil }
        switch Session.autoSelectQuality {
        case "Highest":
            return pool.max()
        case "Low":
            return pool.min()
        case "Optimal":
            return pool.max(by: { adjustedQualityScore($0) < adjustedQualityScore($1) })
        default:
            return pool.max(by: { adjustedQualityScore($0) < adjustedQualityScore($1) })
        }
    }
}

/// Per-mode policy for the streamer's byte-level pre-buffer floor.
/// The single dimension is `minPieces`: how many contiguous head
/// pieces libtorrent must have on disk before `fastForwardTorrent
/// ForRange:` returns YES and `readyToPlay` fires. Below ~3 the
/// moov/cues parse can stall on some MP4/MKV files; above ~8
/// first-frame latency is visibly long on slower swarms.
///
/// There used to be a second, seconds-of-runtime gate ("buffer 4 s
/// of playback ahead before starting") on top of this. It was
/// pulled — once libtorrent has the head pieces, just play. Mid-
/// playback dips are covered by VLC's own `.buffering` state for
/// transient hiccups and by `PlaybackHealthMonitor` for chronic
/// swarm collapses (which surface a "Switch source" prompt).
struct PrebufferPolicy {
    var minPieces: Int

    /// Fast — start as soon as libtorrent has 3 head pieces on disk
    /// (≈3–6 MB). Snappiest first-frame; tightest tolerance for slow
    /// swarms.
    static let fastStrategy     = PrebufferPolicy(minPieces: 3)
    /// Balanced — wait for 4 head pieces (≈4–8 MB). Default; works
    /// even on swarms that are a bit thin.
    static let balancedStrategy = PrebufferPolicy(minPieces: 4)
    /// Smooth — 8 head pieces (≈8–16 MB) before starting. More
    /// upfront wait, more cushion against immediate stalls on
    /// chronically slow connections.
    static let smoothStrategy   = PrebufferPolicy(minPieces: 8)

    /// Resolves the active policy from `Session.bufferingStrategy`.
    @MainActor
    static var current: PrebufferPolicy {
        switch Session.bufferingStrategy {
        case "Smooth":   return .smoothStrategy
        case "Balanced": return .balancedStrategy
        case "Fast":     return .fastStrategy
        default:         return .fastStrategy
        }
    }
}

/// Watches `PTTorrentStatus` updates from `PTTorrentStreamer` and emits
/// at most one `HealthIssue` per session when the swarm looks bad enough
/// to suggest swapping sources. Conservative by design: respects a
/// cold-start grace window, fires only on signals strong enough to
/// indicate the swarm itself is broken (peer collapse, sustained low
/// speed, repeated stalls), and won't re-prompt after dismissal.
///
/// Lifecycle is per-`Torrent`-session: `TorrentPlayerView` owns one
/// `@StateObject` instance and hands it to both `PreloadTorrentViewModel`
/// (pre-buffer phase) and `PlayerViewModel` (mid-playback). The phase
/// flag passed to `observe(status:phase:)` selects which `PTTorrentStatus`
/// field is canonical for stall detection — `bufferingProgress` while
/// pre-buffering, `totalProgress` once playback has begun.
@MainActor
final class PlaybackHealthMonitor: ObservableObject {
    enum HealthIssue: Equatable {
        case bufferStall       // ≥30 s frozen, or ≥2 stalls in 60 s
        case slowStart         // pre-buffer hasn't finished after ~30 s
        case peerCollapse      // peers fell below 3 in the first 2 min
        case sustainedLowSpeed // <500 KB/s for ≥30 s while buffer short

        var localizedMessage: String {
            switch self {
            case .bufferStall:      return "Playback is unstable — try a different source?".localized
            case .slowStart:        return "Source is slow to start — try a different source?".localized
            case .peerCollapse:     return "Source has very few peers — try a different source?".localized
            case .sustainedLowSpeed:return "Download speed is too low — try a different source?".localized
            }
        }
    }

    enum Phase {
        case preBuffer, playback
    }

    /// The non-nil issue currently being shown to the user. Bound to the
    /// toast view; cleared by user dismissal but `hasEmittedIssue` stays
    /// true so we never re-prompt on the same session.
    @Published private(set) var currentIssue: HealthIssue?

    /// `true` once an issue has been emitted in this session. Guardrail
    /// against repeat prompts ("one auto-prompt per session per title").
    private(set) var hasEmittedIssue = false

    let torrentURL: String
    private let sessionStarted = Date()
    private let coldStartGrace: TimeInterval = 30

    private var lastBufferProgress: Float = -1
    private var lastBufferProgressChangedAt = Date()
    private var stallTimestamps: [Date] = []
    private var sustainedLowSpeedSince: Date?
    /// Set when VLC enters `.buffering` mid-playback; cleared when it
    /// returns to `.playing`. Mid-playback stalls are detected from VLC
    /// state rather than streamer `totalProgress` because libtorrent
    /// legitimately throttles downloads when the buffer is full and the
    /// playhead is well behind, which would otherwise look like a stall.
    private var vlcBufferingSince: Date?

    init(torrentURL: String) {
        self.torrentURL = torrentURL
    }

    /// Called from the streamer's progress callback. Already on
    /// MainActor (PTTorrentStreamer dispatches the callback to main).
    func observe(status: PTTorrentStatus, phase: Phase) {
        guard !hasEmittedIssue else { return }
        let now = Date()
        let sinceStart = now.timeIntervalSince(sessionStarted)

        // Track pre-buffer drift always so the watermark is current when
        // grace ends and we don't fire a stall the instant grace closes.
        // Mid-playback we don't drift-track from totalProgress because
        // libtorrent throttles when the buffer is full and the playhead
        // is far behind — that's healthy idleness, not a stall.
        if phase == .preBuffer, status.bufferingProgress != lastBufferProgress {
            lastBufferProgress = status.bufferingProgress
            lastBufferProgressChangedAt = now
        }

        // Cold-start grace — slow first chunks are normal.
        guard sinceStart >= coldStartGrace else { return }

        // Slow start: past grace and pre-buffer hasn't finished.
        if phase == .preBuffer, status.bufferingProgress < 1.0 {
            emit(.slowStart)
            return
        }

        // Pre-buffer stall: bufferingProgress unchanged for ≥10 s. One
        // ≥30 s stall OR two ≥10 s stalls in 60 s emit.
        if phase == .preBuffer {
            let stallDuration = now.timeIntervalSince(lastBufferProgressChangedAt)
            if stallDuration >= 10 {
                stallTimestamps.append(now)
                stallTimestamps = stallTimestamps.filter { now.timeIntervalSince($0) < 60 }
                if stallDuration >= 30 || stallTimestamps.count >= 2 {
                    emit(.bufferStall)
                    return
                }
            }
        } else if let bufferingSince = vlcBufferingSince {
            // Mid-playback stall: VLC has been re-buffering for too long.
            // VLC's `.buffering` state is the actionable signal here — it
            // means playback is paused waiting on data from libtorrent.
            let bufferingDuration = now.timeIntervalSince(bufferingSince)
            if bufferingDuration >= 10 {
                stallTimestamps.append(now)
                stallTimestamps = stallTimestamps.filter { now.timeIntervalSince($0) < 60 }
                if bufferingDuration >= 30 || stallTimestamps.count >= 2 {
                    emit(.bufferStall)
                    return
                }
            }
        }

        // Peer collapse — only meaningful during pre-buffer. Once
        // playback is running, momentary peer dips to 0–2 are normal
        // (peers churn on every reconnect / unchoke cycle) and don't
        // matter as long as VLC isn't buffering — `bufferStall` is
        // the canonical mid-playback signal. Firing peerCollapse
        // during stable playback was the source of the user-reported
        // "Playback unstable" banner appearing while video played
        // fine.
        if phase == .preBuffer, sinceStart < 120, status.peers < 3 {
            emit(.peerCollapse)
            return
        }

        // Sustained low download speed only matters during pre-buffer.
        // Mid-playback the streamer correctly drops speed when buffer is
        // full, so this signal would false-positive on healthy swarms.
        if phase == .preBuffer {
            let kbps = status.downloadSpeed / 1024
            if kbps < 500, status.bufferingProgress < 1.0 {
                if sustainedLowSpeedSince == nil {
                    sustainedLowSpeedSince = now
                } else if now.timeIntervalSince(sustainedLowSpeedSince!) >= 30 {
                    emit(.sustainedLowSpeed)
                    return
                }
            } else {
                sustainedLowSpeedSince = nil
            }
        }
    }

    /// Called from `PlayerViewModel.mediaPlayerStateChanged` when VLC
    /// enters `.buffering`. Used to detect mid-playback stalls without
    /// confusing them with libtorrent's healthy-buffer-full throttling.
    func vlcBufferingDidStart() {
        if vlcBufferingSince == nil { vlcBufferingSince = Date() }
    }

    /// Called when VLC leaves `.buffering` (back to `.playing` or
    /// `.paused`). Resets the mid-playback stall tracker.
    func vlcBufferingDidEnd() {
        vlcBufferingSince = nil
    }

    private func emit(_ issue: HealthIssue) {
        guard !hasEmittedIssue else { return }
        hasEmittedIssue = true
        currentIssue = issue
        PlaybackFailureRegistry.shared.recordFailure(url: torrentURL)
    }

    /// User chose "Keep watching" — drop the toast but don't reset
    /// `hasEmittedIssue` so we don't spam with the same warning.
    func dismissIssue() {
        currentIssue = nil
    }

    /// Clear all pre-buffer-phase state when playback successfully
    /// starts. Pre-buffer signals (`slowStart`, `peerCollapse`,
    /// `sustainedLowSpeed`) describe problems with *getting* video
    /// playing — once VLC is actually rendering frames, those signals
    /// are stale and shouldn't be shown to the user. We do reset
    /// `hasEmittedIssue` here so a genuine *mid-playback* bufferStall
    /// later in the session can still fire (the user shouldn't be
    /// silenced by an early-life slowStart that never reached them).
    func resetForPlayback() {
        currentIssue = nil
        hasEmittedIssue = false
        stallTimestamps = []
        sustainedLowSpeedSince = nil
        vlcBufferingSince = nil
    }
}

@MainActor
class PreloadTorrentViewModel: ObservableObject {
    var torrent: Torrent
    var media: Media
    var watchedProgress: Float = 0.0

    @Published var isProcessing = true
    /// Monotonic 0–1 "ready to play" progress, sourced from
    /// `PTTorrentStatus.bufferingProgress`. The streamer pins this to
    /// 1.0 once the initial head-piece batch is on disk; the
    /// `max(...)` here is defence-in-depth so any future contributor
    /// reading this property gets a non-decreasing value.
    @Published var progress: Float = 0.0
    /// Fraction of the selected file currently on disk (0–1). Sourced
    /// from `PTTorrentStatus.totalProgress` — strictly monotonic,
    /// surfaced in the preload stats panel as "Downloaded".
    @Published var totalProgress: Float = 0.0
    @Published var speed: Int = 0
    @Published var seeds: Int = 0
    var streamer: PTTorrentStreamer?

    @Published var error: Error?
    @Published var showError = false
    @Published var showFileToPlay = false
    @Published var filesToPlay: [String] = []
    @Published var selectedFileToPlay: String? {
        didSet {
            backgroundFileSelectionLock.withLock {
                _backgroundSelectedFile = selectedFileToPlay
            }
        }
    }
    @Published var playerModel: PlayerViewModel?
    @Published var clearCache = ClearCache()

    var onReadyToPlay: (PlayerViewModel) -> Void

    /// Health monitor for this session — observed by the UI to drive the
    /// "try a different source" toast. Owned by `TorrentPlayerView` so it
    /// survives the preload→playback transition.
    let healthMonitor: PlaybackHealthMonitor

    /// Forwards the monitor's `currentIssue` so the view doesn't have to
    /// reach through a nested `ObservableObject` (which `@StateObject`
    /// won't republish without explicit Combine plumbing).
    @Published var healthIssue: PlaybackHealthMonitor.HealthIssue?
    private var healthIssueSubscription: AnyCancellable?

    /// Caller hook for the toast's "Switch" action — tear down the
    /// current streamer and ask the parent flow to pick a different
    /// source. The `Float` is the 0–1 resume position to apply on the
    /// replacement source (always 0 from pre-buffer; mediaplayer position
    /// from mid-playback). `nil` if the parent doesn't support swapping.
    var onRequestSwitchSource: ((Float) -> Void)?

    /// `true` when this preload was kicked off by a source swap, so the
    /// player should auto-resume at `watchedProgress` without prompting
    /// the user with the "Resume Playing / Start from Beginning" alert.
    var isResumingFromSwap: Bool = false

    /// Set true 30 s after play starts, even when the health monitor
    /// hasn't fired anything yet. Drives the inline "Taking a while?
    /// Switch source" link on `PreloadTorrentView` so users with an
    /// itchy trigger finger can swap without waiting for the monitor
    /// to detect a problem (the monitor's cold-start grace is 30 s,
    /// which is too long for a user who just wants to try a different
    /// release). Hidden whenever a real `healthIssue` is showing —
    /// the toast takes over.
    @Published var showSwitchSourcePrompt: Bool = false

    // Storage that libtorrent's background thread (com.popcorntimetv.popcorntorrent.alerts)
    // can read without crossing into MainActor isolation.
    nonisolated private let mediaSnapshot: Media
    nonisolated(unsafe) private var _backgroundSelectedFile: String?
    nonisolated private let backgroundFileSelectionLock = NSLock()

    init(
        torrent: Torrent,
        media: Media,
        healthMonitor: PlaybackHealthMonitor? = nil,
        onReadyToPlay: @escaping (PlayerViewModel) -> Void
    ) {
        self.torrent = torrent
        self.media = media
        self.mediaSnapshot = media
        self.healthMonitor = healthMonitor ?? PlaybackHealthMonitor(torrentURL: torrent.url)
        self.onReadyToPlay = onReadyToPlay

        healthIssueSubscription = self.healthMonitor.$currentIssue
            .receive(on: RunLoop.main)
            .assign(to: \.healthIssue, on: self)
    }

    /// Toast "Switch" tapped during pre-buffer. Cancels the current
    /// streamer (so libtorrent stops grinding on the bad swarm) and
    /// hands control to the parent to pick a replacement. Pre-buffer
    /// has no playback position yet, so resume is 0 — the parent will
    /// honor any saved watched-progress on the new session.
    func requestSwitchSource() {
        healthMonitor.dismissIssue()
        streamer?.cancelStreamingAndDeleteData(false)
        streamer = nil
        onRequestSwitchSource?(0)
    }
    
    func cancel() {
        let isPlaying = playerModel != nil
        if !isPlaying {
            self.streamer?.cancelStreamingAndDeleteData(false)
        }
    }
    
    func playTorrent() {
        // Idempotent. The `PreloadTorrentView` is mounted twice in a
        // single play session: once under the `.preload` state, then
        // a second time inside the `.play` state's ZStack (so the
        // preload screen stays visible until VLC renders the first
        // frame). The second mount fires `.onAppear` and would, by
        // default, kick off a brand-new streamer that orphans the
        // already-bound `playerModel` and stalls playback at 100 %
        // buffered. Guarding on `playerModel != nil` short-circuits
        // the re-entry so the original streamer keeps serving bytes
        // to VLC.
        guard playerModel == nil else { return }

        // Apply the user's Buffering Strategy to the streamer's
        // byte-level pre-buffer floor. Without this, picking
        // Fast/Balanced/Smooth in Settings only changed the Swift-
        // side adaptive gate while libtorrent's MIN_PIECES stayed
        // hardcoded at 4–6 — so the user-visible difference between
        // strategies was muted. Setting the override here makes the
        // setting actually move the floor (Fast=3, Balanced=4,
        // Smooth=8 head pieces).
        PTTorrentStreamer.setMinPiecesOverride(PrebufferPolicy.current.minPieces)

        // Honour an explicit pre-set `watchedProgress` (set by source-swap
        // flows so the new torrent picks up where the failed one left
        // off). Otherwise fall back to the saved watchlist progress.
        if watchedProgress == 0 {
            if let _ = media as? Movie {
                watchedProgress = WatchedlistManager<Movie>.movie.currentProgress(media.id)
            } else if let _ = media as? Episode {
                watchedProgress = WatchedlistManager<Episode>.episode.currentProgress(media.id)
            }
        }

        // Surface the inline "Switch source" link 30 s in — at that
        // point either the download is genuinely struggling or the
        // user is impatient enough to want an out. Shown once and
        // then persists (we don't toggle it off after firing) so
        // the user has a clear, stable "swap" affordance until the
        // preload completes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            // Don't show if we're already past pre-buffer (player
            // running) or if the health monitor already surfaced
            // something — that path has its own Switch wording.
            if self.playerModel == nil, self.healthIssue == nil {
                self.showSwitchSourcePrompt = true
            }
        }
        
        #if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = true
        let finishedLoading: () -> Void = {
            UIApplication.shared.isIdleTimerDisabled = false
//            let flag = UIDevice.current.userInterfaceIdiom != .tv
        }
        #else
        let finishedLoading: () -> Void = { }
        #endif
        
        self.play(fromFileOrMagnetLink: torrent.url, nextEpisodeInSeries: nil, finishedLoadingBlock: finishedLoading)
    }
    

    
    /**
     Start playing movie or episode locally.
     
     - Parameter fromFileOrMagnetLink:  The url pointing to a .torrent file, a web adress pointing to a .torrent file to be downloaded or a magnet link.
     - Parameter nextEpisodeInSeries:   If media is an episode, pass in the next episode of the series, if applicable, for a better UX for the user.
     - Parameter finishedLoadingBlock:  Block thats called when torrent is finished loading.
     */
    func play(
        fromFileOrMagnetLink url: String,
        nextEpisodeInSeries nextEpisode: Episode? = nil,
        finishedLoadingBlock: @escaping () -> Void)
    {
        let playBlock: (URL, URL, Media, Episode?) -> Void = { (videoFileURL, videoFilePath, media, nextEpisode) in
            DispatchQueue.main.async {
                let playerModel = PlayerViewModel(
                    media: media,
                    fromUrl: videoFileURL,
                    localUrl: videoFilePath,
                    directory: videoFilePath.deletingLastPathComponent(),
                    streamer: self.streamer!,
                    healthMonitor: self.healthMonitor
                )
                playerModel.startPosition = self.watchedProgress
                playerModel.onRequestSwitchSource = self.onRequestSwitchSource
                if self.isResumingFromSwap {
                    // Skip the resume-or-restart prompt — user already
                    // chose to switch with a specific resume timestamp.
                    playerModel.resumePlayback = true
                }
                // Wipe any pre-buffer health-monitor state before
                // `PlayerView` observes `currentIssue`. Without this,
                // a `slowStart` / `peerCollapse` that fired during
                // preload would carry over into the player overlay,
                // showing "Source is slow to start" *after* playback
                // has actually begun.
                self.healthMonitor.resetForPlayback()
                finishedLoadingBlock()
                self.playerModel = playerModel
                self.onReadyToPlay(playerModel)
            }
        }
        
        if hasDownloaded, let download = associatedDownload {
            download.play { (videoFileURL, videoFilePath) in
                self.streamer = download
                playBlock(videoFileURL, videoFilePath, self.media, nextEpisode)
            }
            return
        }
        
        if isDownloading, let download = associatedDownload {
            download.play { (videoFileURL, videoFilePath) in
                self.streamer = download
                playBlock(videoFileURL, videoFilePath, self.media, nextEpisode)
            }
            return
        }
        
        let loadingBlock: (PTTorrentStatus) -> Void = { status in
            self.isProcessing = false
            self.progress = max(self.progress, status.bufferingProgress)
            self.totalProgress = max(self.totalProgress, status.totalProgress)
            self.speed = Int(status.downloadSpeed)
            self.seeds = Int(status.seeds)
            // Once `playerModel` is set, playback has begun and
            // PlayerViewModel has taken over health monitoring via
            // `PTTorrentStatusDidChange` with `phase: .playback`. The
            // streamer keeps firing progress here in the background —
            // ignore it to avoid double-counting and to stop pre-buffer
            // signals (slowStart) from emitting during playback.
            if self.playerModel == nil {
                self.healthMonitor.observe(status: status, phase: .preBuffer)
            }
        }
        let errorBlock: (Error) -> Void = { error in
            self.error = error
            self.showError = true
        }

        
        if url.hasPrefix("magnet") || (url.hasSuffix(".torrent") && !url.hasPrefix("http")) {
            // Release any warm streamer holding this magnet — see the
            // "critical invariant" docstring on `TorrentSessionWarmer`.
            // Cached pieces stay on disk so the play streamer still
            // benefits from the warmer's work.
            TorrentSessionWarmer.shared.release(magnetURL: url)
            self.streamer = PTTorrentStreamer()
            // PTTorrentStreamerSelection is invoked from libtorrent's background queue.
            // Declare the closure @Sendable so Swift 6 doesn't inherit @MainActor from
            // play()'s context. selectFileToStream is itself nonisolated.
            let selector: @Sendable ([String], [NSNumber]) -> Int32 = { [self] fileNames, fileSizes in
                self.selectFileToStream(fileNames: fileNames, fileSizes: fileSizes)
            }
            self.streamer!.startStreaming(fromMultiTorrentFileOrMagnetLink: url, progress: { (status) in
                loadingBlock(status)
            }, readyToPlay: { (videoFileURL, videoFilePath) in
                // Record a successful play for app-launch restore. Only
                // saved on `readyToPlay` (not on `play()`) so failed /
                // unreachable magnets aren't kept around to waste
                // session warmup at next launch.
                Session.recordRecentlyPlayed(magnetURL: url)
                playBlock(videoFileURL, videoFilePath, self.media, nextEpisode)
            }, failure: { error in
                DispatchQueue.main.async {
                    errorBlock(error)
                }
            }, selectFileToStream: selector)
        } else {
            Task { @MainActor in
                do {
                    let fileUrl = try await PopcornKit.downloadTorrentFile(url)
                    self.play(fromFileOrMagnetLink: fileUrl.absoluteString, nextEpisodeInSeries: nil, finishedLoadingBlock: finishedLoadingBlock)
                } catch {
                    errorBlock(error)
                }
            }
        }
    }
    
    /// The download, either completed or downloading, that is associated with this media object.
    var associatedDownload: PTTorrentDownload? {
        let id = self.media.id
        let array = PTTorrentDownloadManager.shared().activeDownloads + PTTorrentDownloadManager.shared().completedDownloads
        return array.first(where: {($0.mediaMetadata[MPMediaItemPropertyPersistentID] as? String) == id})
    }
    
    /// Boolean value indicating whether the media is currently downloading.
    var isDownloading: Bool {
        let id = self.media.id
        return PTTorrentDownloadManager.shared().activeDownloads.first(where: {($0.mediaMetadata[MPMediaItemPropertyPersistentID] as? String) == id}) != nil
    }
    
    /// Boolean value indicating whether the media has been downloaded.
    var hasDownloaded: Bool {
        let id = self.media.id
        return PTTorrentDownloadManager.shared().completedDownloads.first(where: {($0.mediaMetadata[MPMediaItemPropertyPersistentID] as? String) == id}) != nil
    }
    
    var isNotEnoughSpaceError: Bool {
        if let error = error as NSError?, error.code == -4 && error.domain == "com.popcorntimetv.popcorntorrent.error" {
            return true
        }
        return false
    }

    /// Called from libtorrent's background alerts queue. Must remain `nonisolated`
    /// so it can run there without tripping Swift 6's main-actor executor check.
    nonisolated func selectFileToStream(fileNames: [String], fileSizes: [NSNumber]) -> Int32 {
        if fileNames.count == 1 {
            return Int32(0)
        }

        var files = Array(zip(fileNames, fileSizes).enumerated())

        /// for series, keep only files with format: E01
        if let episode = mediaSnapshot as? Episode {
            let findByEpisode = String(format: "E%02d", episode.episode)
            files = files.filter { _, item in
                item.0.lowercased().contains(findByEpisode.lowercased())
            }
        }

        /// the biggest file
        let max = files.max { $0.element.1.int64Value < $1.element.1.int64Value  }
        if let biggestFileIndex = max?.offset {
            return Int32(biggestFileIndex)
        }

        // let user select
        Task { @MainActor [weak self] in
            self?.filesToPlay = fileNames
            self?.showFileToPlay = true
        }

        while true {
            let selection = backgroundFileSelectionLock.withLock { _backgroundSelectedFile }
            if selection != nil { break }
            Thread.sleep(forTimeInterval: 1)
        }
        let selected = backgroundFileSelectionLock.withLock { _backgroundSelectedFile }!
        let index = fileNames.firstIndex(of: selected) ?? 0
        return Int32(index)
    }
}
