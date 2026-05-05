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
#if canImport(UIKit)
import UIKit
#endif

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
@MainActor
final class MoviePrefetcher: ObservableObject {
    private var streamer: PTTorrentStreamer?
    private var prefetchedURL: String?

    /// Pick the most-likely-played torrent for `media` (using the same
    /// `adjustedQualityScore` ranking the auto-play path uses) and
    /// kick off a background streamer for it. Idempotent: a second
    /// call with the same target is a no-op while the first is in
    /// flight; switching to a different target cancels the previous.
    func start(media: Media) {
        // Don't prefetch when the user explicitly wants the picker —
        // we can't guess which source they'll choose, and prefetching
        // the wrong one wastes bandwidth.
        guard Session.autoSelectQuality != "Selectable" else { return }

        let candidates = media.torrents
        guard let target = candidates.max(by: { adjustedQualityScore($0) < adjustedQualityScore($1) }) else {
            return
        }
        guard prefetchedURL != target.url else { return }

        cancel()
        prefetchedURL = target.url

        let s = PTTorrentStreamer()
        self.streamer = s
        s.startStreaming(
            fromMultiTorrentFileOrMagnetLink: target.url,
            progress: { _ in },
            readyToPlay: { _, _ in },
            failure: { _ in },
            selectFileToStream: { _, fileSizes in
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
        )
    }

    /// Tear down the prefetch streamer. Pass `false` to
    /// `cancelStreamingAndDeleteData` so the partial data on disk is
    /// kept — the play streamer can pick up from where prefetch left
    /// off if the user taps Play immediately.
    func cancel() {
        streamer?.cancelStreamingAndDeleteData(false)
        streamer = nil
        prefetchedURL = nil
    }
}

/// Per-mode policy for the adaptive pre-buffer gate. Optimal favours
/// smoothness: it waits for a meaningful buffer AND a sustainable
/// download rate before starting playback. Highest still waits a bit
/// (high-res files have less margin for error). Normal and Selectable
/// take libtorrent's default fast-start path because the user explicitly
/// picked low-resource or manual modes.
struct PrebufferPolicy {
    /// Baseline seconds of decoded playback to buffer ahead before
    /// starting. The runtime adds bumps for resolution, swarm health,
    /// and download-speed variance. `nil` means the adaptive gate is
    /// skipped entirely — libtorrent's `bufferingProgress = 1.0` is the
    /// only signal.
    var targetSeconds: Float?

    /// Minimum sustained download speed as a multiple of the file's
    /// bitrate. `1.2` means we want 20 % headroom — a fat pre-buffer
    /// drains 25 minutes in if download speed only matches the bitrate
    /// exactly. `nil` skips the rate gate.
    var rateRatio: Float?

    /// How long the adaptive gate will hold playback before giving
    /// up and starting anyway. Only meaningful when `targetSeconds
    /// != nil` (otherwise the gate is bypassed). Per-strategy so
    /// Fast / Balanced / Smooth can each pick a sensible ceiling.
    var maxWaitSeconds: TimeInterval = 30

    /// Number of head pieces libtorrent must have on disk before
    /// `PTTorrentStreamer.fastForwardTorrentForRange:` returns YES
    /// for VLC's first range request. Plumbed via
    /// `PTTorrentStreamer.setMinPiecesOverride:` — actually changes
    /// the byte-level pre-buffer wait, not just the Swift-side
    /// adaptive gate. Below ~3 the moov/cues parse can stall on
    /// some MP4/MKV files; above ~8 first-frame latency is visibly
    /// long on slower swarms.
    var minPieces: Int = 4

    // Three named presets the user picks via Settings →
    // `Buffering Strategy`.
    //
    // `Fast` is properly immediate — adaptive gate skipped entirely
    // (`targetSeconds: nil`), and libtorrent's pre-buffer is dropped
    // to 3 head pieces (≈3–6 MB). First-frame latency on a healthy
    // swarm settles around 1–3 s.
    //
    // `Balanced` keeps the proven 4-piece floor (≈4–8 MB) and gates
    // playback start on ~4 s of buffered playback. Buffer absorbs
    // short-term speed fluctuations.
    //
    // `Smooth` is the most conservative — 8 piece pre-buffer
    // (≈8–16 MB) and 8 s playback buffer; if the rate genuinely
    // can't sustain bitrate, the in-playback `bufferStall` health
    // monitor surfaces a Switch suggestion mid-playback.
    static let fastStrategy     = PrebufferPolicy(targetSeconds: nil, rateRatio: nil, maxWaitSeconds: 15, minPieces: 3)
    static let balancedStrategy = PrebufferPolicy(targetSeconds: 4,   rateRatio: nil, maxWaitSeconds: 30, minPieces: 4)
    static let smoothStrategy   = PrebufferPolicy(targetSeconds: 8,   rateRatio: nil, maxWaitSeconds: 60, minPieces: 8)
    /// Used for `Selectable` quality mode — user is picking
    /// manually each play, so we trust their judgement and start
    /// immediately without adaptive gating.
    static let immediate        = PrebufferPolicy(targetSeconds: nil, rateRatio: nil, minPieces: 3)

    /// Resolves the active policy from
    /// `Session.bufferingStrategy`, with `Selectable` quality short-
    /// circuiting to immediate-start regardless of the strategy
    /// pick (the user is making the choice anyway, no second-
    /// guessing).
    @MainActor
    static var current: PrebufferPolicy {
        if Session.autoSelectQuality == "Selectable" {
            return .immediate
        }
        switch Session.bufferingStrategy {
        case "Smooth":   return .smoothStrategy
        case "Balanced": return .balancedStrategy
        case "Fast":     return .fastStrategy
        default:         return .fastStrategy
        }
    }
}

/// Phase the adaptive pre-buffer gate is in — drives the friendly
/// waiting message rendered by `PreloadTorrentView`.
enum AdaptiveBufferStatus: Equatable {
    /// libtorrent hasn't fired `readyToPlay` yet; we're still in the
    /// initial download phase. The progress bar carries the message,
    /// no banner is needed.
    case initialBuffering

    /// libtorrent says ready, but we haven't accumulated enough data
    /// ahead of the playhead for our quality target. `have` and `need`
    /// are seconds of decoded playback.
    case waitingForBuffer(have: Float, need: Float)

    /// We have enough buffer, but observed download speed isn't fast
    /// enough to sustain the bitrate without later stalls.
    case waitingForRate(currentBps: Int, requiredBps: Int)

    /// Both gates passed — playback can start now.
    case ready

    /// One-line status to render under the linear progress bar. Always
    /// returns a string so the preload view can keep a single, stable
    /// status row instead of switching between an indeterminate spinner
    /// and a labeled progress bar (Apple HIG: don't mix determinate
    /// and indeterminate progress in the same flow).
    var statusMessage: String {
        switch self {
        case .initialBuffering:
            return "Connecting to source…".localized
        case .ready:
            return "Starting playback…".localized
        case .waitingForBuffer(let have, let need):
            let haveStr = String(format: "%.0f", have)
            let needStr = String(format: "%.0f", need)
            return String(format: "Buffering for smooth playback — %@s of %@s ready…".localized, haveStr, needStr)
        case .waitingForRate(let currentBps, let requiredBps):
            let cur = ByteCountFormatter.string(fromByteCount: Int64(currentBps), countStyle: .binary)
            let need = ByteCountFormatter.string(fromByteCount: Int64(requiredBps), countStyle: .binary)
            return String(format: "Waiting for stable connection — %@/s, need %@/s for smooth playback…".localized, cur, need)
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
    @Published var progress: Float = 0.0
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

    /// Drives the friendly "why are we waiting" banner in
    /// `PreloadTorrentView`. Updated as the adaptive gate evaluates each
    /// `PTTorrentStatus` tick after libtorrent fires `readyToPlay`.
    @Published var adaptiveStatus: AdaptiveBufferStatus = .initialBuffering

    /// Set true 10 s after play starts, even when the health monitor
    /// hasn't fired anything yet. Drives the inline "Taking a while?
    /// Switch source" link on `PreloadTorrentView` so users with an
    /// itchy trigger finger can swap without waiting for the monitor
    /// to detect a problem (the monitor's cold-start grace is 30 s,
    /// which is too long for a user who just wants to try a different
    /// release). Hidden whenever a real `healthIssue` is showing —
    /// the toast takes over.
    @Published var showSwitchSourcePrompt: Bool = false

    /// Stored playBlock invocation kept until the adaptive gate clears.
    /// libtorrent's `readyToPlay` callback hands us this; we deferr it
    /// while we wait for buffer + rate criteria.
    private var deferredPlayBlock: (() -> Void)?

    /// When the adaptive gate started holding playback. Used to enforce
    /// the strategy-specific `maxWaitSeconds` upper bound so the user
    /// is never stuck on the loading screen because their connection
    /// can't satisfy the rate gate (e.g. 4K bitrate above their
    /// available bandwidth — the rate gate would otherwise hold
    /// forever waiting for an impossible threshold).
    private var deferredSince: Date?

    /// Rolling 10 samples of `downloadSpeed` for variance + average.
    private var speedSamples: [Int] = []
    private let maxSpeedSamples = 10

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
            self.progress = status.bufferingProgress
            self.speed = Int(status.downloadSpeed)
            self.seeds = Int(status.seeds)
            self.recordSpeedSample(Int(status.downloadSpeed))
            // Once `playerModel` is set, playback has begun and
            // PlayerViewModel has taken over health monitoring via
            // `PTTorrentStatusDidChange` with `phase: .playback`. The
            // streamer keeps firing progress here in the background —
            // ignore it to avoid double-counting and to stop pre-buffer
            // signals (slowStart) from emitting during playback.
            if self.playerModel == nil {
                self.healthMonitor.observe(status: status, phase: .preBuffer)
            }
            // Adaptive pre-buffer gate. libtorrent's readyToPlay fires
            // when its internal threshold is met, but for high-res
            // sources that's often not enough buffer to play smoothly.
            // We hold the deferred playBlock until both the buffer-
            // headroom and sustained-rate criteria pass.
            if let deferred = self.deferredPlayBlock {
                let next = self.evaluateAdaptiveGate(status: status)
                self.adaptiveStatus = next
                if next == .ready {
                    self.deferredPlayBlock = nil
                    deferred()
                }
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
                let block = {
                    playBlock(videoFileURL, videoFilePath, self.media, nextEpisode)
                }
                // If the user picked a fast-start mode (Normal /
                // Selectable / unknown), or we don't have the metadata
                // we need to evaluate the adaptive gate, fire
                // immediately. Otherwise hand the block to loadingBlock
                // which will fire it once the gate clears.
                if PrebufferPolicy.current.targetSeconds == nil {
                    block()
                } else {
                    self.deferredPlayBlock = block
                    self.deferredSince = Date()
                    self.adaptiveStatus = .waitingForBuffer(have: 0, need: 0)
                }
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

    // MARK: - Adaptive pre-buffer gate

    /// Append the current download speed to the rolling sample window.
    /// 10 samples ≈ 5 s of history at libtorrent's ~2 Hz callback rate,
    /// which matches the spec's "average speed over the last 10 s."
    private func recordSpeedSample(_ speed: Int) {
        speedSamples.append(speed)
        if speedSamples.count > maxSpeedSamples {
            speedSamples.removeFirst(speedSamples.count - maxSpeedSamples)
        }
    }

    /// Decide whether the adaptive criteria are met yet. Called once
    /// per progress tick after libtorrent fired its `readyToPlay`.
    private func evaluateAdaptiveGate(status: PTTorrentStatus) -> AdaptiveBufferStatus {
        let policy = PrebufferPolicy.current
        guard let baseTarget = policy.targetSeconds else {
            return .ready  // Fast-start policy — gate is open by default.
        }

        // Hard timeout — if we've been holding playback for over the
        // strategy's `maxWaitSeconds`, give up and play anyway.
        // Better a small buffer than the user staring at the wait
        // screen because their network can't physically satisfy the
        // rate gate.
        if let deferredSince, Date().timeIntervalSince(deferredSince) > policy.maxWaitSeconds {
            return .ready
        }

        // Without media runtime we can't translate bytes-buffered into
        // seconds-buffered, so the seconds-based gate is meaningless.
        // libtorrent has already fired `readyToPlay` by the time we
        // reach this code, so trust its signal and let playback start.
        guard let durationSec = mediaDurationSeconds, durationSec > 0 else {
            return .ready
        }

        // Buffer-headroom target (seconds), tuned to swarm + content.
        // Bumps are deliberately small — the strategy preset already
        // reflects the user's preference, the bumps just add caution
        // when the swarm/content actively warrants it. Earlier values
        // (4K +3, marginal +6, weak +15, variance +5) added many
        // seconds of perceived wait on common edge cases.
        var target = baseTarget
        let q = (torrent.quality ?? "").lowercased()
        if q == "2160p" || q == "4k" {
            target += 2  // bigger frames + decoder warmup
        }
        if status.peers < 3 {
            target += 10  // very thin swarm — be patient or it'll stall immediately
        } else if status.peers < 10 {
            target += 4   // marginal swarm
        }
        if speedVariance > 0.5 {
            target += 3   // speed flapping → drain risk
        }

        let buffered = secondsBuffered(status: status)
        if buffered < target {
            return .waitingForBuffer(have: buffered, need: target)
        }

        // Sustained-rate gate. Only enforced when we can compute the
        // file's bitrate (filesize + media runtime both known) — without
        // it, we'd block forever on metadata gaps.
        if let rateRatio = policy.rateRatio,
           let bitrate = fileBitrate, bitrate > 0 {
            let avg = avgDownloadSpeed
            let required = Int(Double(bitrate) * Double(rateRatio))
            if avg < required {
                return .waitingForRate(currentBps: avg, requiredBps: required)
            }
        }

        return .ready
    }

    /// Approximate seconds of decoded playback already downloaded.
    /// libtorrent's sequential prioritisation makes `totalProgress`
    /// roughly equal to "fraction of the playhead consumable now,"
    /// so multiplying by media runtime gives a useful proxy.
    private func secondsBuffered(status: PTTorrentStatus) -> Float {
        guard let durationSec = mediaDurationSeconds, durationSec > 0 else { return 0 }
        return Float(durationSec) * status.totalProgress
    }

    /// Media runtime in seconds, drawn from `Movie.runtime` or the
    /// parent `Show.runtime` for episodes. `nil` when unknown — the
    /// adaptive gate then falls back to a no-op via the bitrate check.
    private var mediaDurationSeconds: Int? {
        if let movie = media as? Movie, movie.runtime > 0 {
            return movie.runtime * 60
        }
        if let episode = media as? Episode, let runtime = episode.show?.runtime, runtime > 0 {
            return runtime * 60
        }
        return nil
    }

    /// Parse `Torrent.size` (e.g. "2.5 GB", "850 MB") into bytes. The
    /// popcorn-api reports sizes as human-readable strings rather than
    /// raw byte counts, so this is the canonical conversion point.
    private var torrentSizeBytes: Int64? {
        return Self.parseSize(torrent.size)
    }

    private static func parseSize(_ size: String?) -> Int64? {
        guard let s = size else { return nil }
        let parts = s.split(separator: " ").map(String.init)
        guard parts.count >= 2, let value = Double(parts[0]) else { return nil }
        let multiplier: Double
        switch parts[1].uppercased() {
        case "GB":  multiplier = 1_073_741_824
        case "MB":  multiplier = 1_048_576
        case "KB":  multiplier = 1024
        case "B":   multiplier = 1
        default:    return nil
        }
        return Int64(value * multiplier)
    }

    /// File bitrate in bytes/sec — the rate the playhead consumes data
    /// at. Used by the sustained-rate gate to decide if download speed
    /// is healthy enough to sustain playback. `nil` when filesize or
    /// runtime are unknown.
    private var fileBitrate: Int? {
        guard let bytes = torrentSizeBytes, bytes > 0,
              let durationSec = mediaDurationSeconds, durationSec > 0 else {
            return nil
        }
        return Int(Double(bytes) / Double(durationSec))
    }

    /// Average of the last `maxSpeedSamples` download-speed samples.
    private var avgDownloadSpeed: Int {
        guard !speedSamples.isEmpty else { return 0 }
        return speedSamples.reduce(0, +) / speedSamples.count
    }

    /// Coefficient of variation (stddev / mean) of the speed window.
    /// Above ~0.5 means download speed is flapping enough that the
    /// adaptive gate adds extra buffer headroom — variable swarms
    /// drain a fixed buffer faster than steady ones at the same mean.
    private var speedVariance: Double {
        guard speedSamples.count >= 5 else { return 0 }
        let n = Double(speedSamples.count)
        let mean = Double(speedSamples.reduce(0, +)) / n
        guard mean > 0 else { return 1 }
        let sumSquares = speedSamples.map { pow(Double($0) - mean, 2) }.reduce(0, +)
        let stddev = sqrt(sumSquares / n)
        return stddev / mean
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
