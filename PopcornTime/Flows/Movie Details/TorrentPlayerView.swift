//
//  MediaPlayerView.swift
//  MediaPlayerView
//
//  Created by Alexandru Tudose on 03.08.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit

struct TorrentPlayerView: View {
    var torrent: Torrent
    var media: Media
    var nextEpisode: NextEpisode?
    /// Resume position (0–1) to apply when the underlying player starts.
    /// Set on a source-swap so the new torrent picks up where the failed
    /// one left off; defaults to 0 (PreloadTorrentViewModel will then
    /// fall back to the saved watched-progress for fresh launches).
    var resumeAt: Float = 0
    /// Bubbled up from the in-player toast — the parent uses this to
    /// pick a replacement torrent and re-present the fullScreenContent
    /// with the new source. `nil` for entry points (downloads, external
    /// magnets) that have only one available torrent and can't swap.
    var onSwitchSource: ((_ resumeAt: Float) -> Void)?

    /// One health monitor per torrent session. Survives the
    /// preload→playback transition by living on the parent view; a fresh
    /// instance is created whenever this view is re-initialised with a
    /// different torrent.
    @StateObject private var healthMonitor: PlaybackHealthMonitor

    init(
        torrent: Torrent,
        media: Media,
        nextEpisode: NextEpisode? = nil,
        resumeAt: Float = 0,
        onSwitchSource: ((_ resumeAt: Float) -> Void)? = nil
    ) {
        self.torrent = torrent
        self.media = media
        self.nextEpisode = nextEpisode
        self.resumeAt = resumeAt
        self.onSwitchSource = onSwitchSource
        _healthMonitor = StateObject(wrappedValue: PlaybackHealthMonitor(torrentURL: torrent.url))
    }

    indirect enum State_ {
        case none
        case preload(PreloadTorrentViewModel)
        /// Player is mounted (so VLC starts decoding) but the preload
        /// screen stays on top until VLC actually renders the first
        /// frame. `playerModel.isLoading` flips to false from
        /// `mediaPlayerTimeChanged` at exactly that moment, and the
        /// preload cover is removed without an intermediate black
        /// gap. Keeping `preloadModel` in this state lets the same
        /// view (with its title + blurred backdrop + spinner) carry
        /// across the handoff.
        case play(PreloadTorrentViewModel, PlayerViewModel)
        case next(TorrentPlayerView)
    }
    @State var state: State_ = .none

    var body: some View {
        switch state {
        case .none:
            Color.black
                .onAppear{
                    load()
                }
        case .preload(let preloadModel):
            PreloadTorrentView(viewModel: preloadModel)
                .background(Color.black)
        case .play(let preloadModel, let playerModel):
            // Extracted into a subview so `playerModel` can be held as
            // `@ObservedObject` — without that wrapper SwiftUI never
            // re-renders when `isLoading` flips false (the captured
            // enum-payload value isn't observed), and the preload
            // cover stays up forever even though VLC is already
            // playing audio + video underneath.
            PlayingWithPreloadCover(
                preloadModel: preloadModel,
                playerModel: playerModel,
                upNextView: upNextView(playerModel: playerModel)
            )
            // Next-episode prefetch is currently disabled — same
            // reason as `App.swift`'s `warmAllRecentlyPlayed`
            // call: the warmer infrastructure has been a
            // consistent source of crashes and piece-priority
            // contention. Re-introduce after we have a way for the
            // warm streamer to *not* compete for download
            // bandwidth with the active play streamer.
        case .next(let nextView):
            nextView
        }
    }

    /// Magnet URL of the next episode's same-quality torrent — what
    /// `upNextView`'s tap action actually plays. Returning the matching
    /// quality (rather than the absolute Optimal pick) ensures the
    /// prefetched data matches the file the play streamer will request.
    private var nextEpisodeMagnetURL: String? {
        guard let nextEpisode = nextEpisode,
              let nextTorrent = nextEpisode.episode.torrents.first(where: { $0.quality == torrent.quality }) else {
            return nil
        }
        return nextTorrent.url
    }

    func load() {
        // Capture the preload model in `onReadyToPlay` so the .play
        // state can carry it forward — the preload cover stays on
        // screen (over the freshly mounted PlayerView) until VLC
        // actually renders a frame.
        var preloadModel: PreloadTorrentViewModel!
        preloadModel = PreloadTorrentViewModel(
            torrent: torrent,
            media: media,
            healthMonitor: healthMonitor,
            onReadyToPlay: { playerModel in
                self.state = .play(preloadModel, playerModel)
            }
        )
        preloadModel.onRequestSwitchSource = onSwitchSource
        if resumeAt > 0 {
            // Honour swap-resume position by overriding the saved
            // watched-progress that playTorrent() would otherwise read,
            // and skip the resume-or-restart prompt — the user already
            // committed to resuming when they tapped Switch source.
            preloadModel.watchedProgress = resumeAt
            preloadModel.isResumingFromSwap = true
        }
        self.state = .preload(preloadModel)
    }

    @ViewBuilder
    func upNextView(playerModel: PlayerViewModel) -> UpNextView? {
        if let nextEpisode = nextEpisode,
           let episode = self.nextEpisode?.episode,
           let torrent = episode.torrents.first(where: {$0.quality == self.torrent.quality}) {
            UpNextView(episode: episode, show: nextEpisode.show, playerModel: playerModel) {
                self.state = .next(TorrentPlayerView(torrent: torrent, media: episode, nextEpisode: nextEpisode.next()))
            }
        }
    }
}

/// `PlayerView` with the preload screen overlaid on top until VLC
/// renders the first frame. `playerModel` is held as `@ObservedObject`
/// so SwiftUI re-renders this view when `isLoading` flips false —
/// without the wrapper the captured enum payload isn't observed and
/// the preload cover would stay up indefinitely.
struct PlayingWithPreloadCover: View {
    let preloadModel: PreloadTorrentViewModel
    @ObservedObject var playerModel: PlayerViewModel
    var upNextView: UpNextView?

    var body: some View {
        ZStack {
            PlayerView(upNextView: upNextView)
                .environmentObject(playerModel)
                .background(Color.black)
            if playerModel.isLoading {
                PreloadTorrentView(viewModel: preloadModel)
                    .background(Color.black)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: playerModel.isLoading)
    }
}

struct MediaPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        TorrentPlayerView(torrent: Torrent(), media: Movie.dummy())
            .preferredColorScheme(.dark)
    }
}
