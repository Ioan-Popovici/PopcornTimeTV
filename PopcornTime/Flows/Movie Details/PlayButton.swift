//
//  PlayButton.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 21.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
import Combine

struct PlayButton: View {
    let theme = Theme()

    var media: Media
    @State var showTorrent: PlayTorrent?
    /// URLs of torrents the user has already tried in this session and
    /// rejected via "Switch source" — excluded from the swap picker
    /// next time so the user doesn't accidentally re-pick a known-bad
    /// source. Cleared on every fresh Play tap.
    @State var triedURLs: Set<String> = []
    /// Carried across the dismiss-then-present transition when the user
    /// taps Switch source — once the player has dismissed, we use this
    /// to open the swap picker with the right resume position queued up.
    @State private var swapPending: SwapPending?
    @State private var showingSwapPicker = false

    // `MoviePrefetcher` invocation is currently disabled — same
    // family of issues as `TorrentSessionWarmer.warmAllRecentlyPlayed`
    // in `App.swift`. The trace caught it churning targets as torrents
    // merge in (`start 720p → cancel → start 480p → cancel` over ~1 s)
    // and crashing libtorrent with `EXC_BAD_ACCESS` in
    // `peer_connection::on_receive_data` — peer connections receiving
    // data after their parent torrent was removed via the cancel path.
    // The class stays in `PreloadTorrentViewModel.swift` for later
    // re-introduction once prefetch can run on an isolated libtorrent
    // session (separate from the play session) so cancel can't race
    // with in-flight peer I/O on a torrent the play streamer cares
    // about.

    struct PlayTorrent: Identifiable, Equatable {
        /// Compose id from URL + resume to force `fullScreenContent` to
        /// re-present when we swap to a new source mid-session — even
        /// though `Identifiable` would otherwise match by torrent.id
        /// alone, swap flows need a guaranteed view rebuild.
        var id: String { torrent.id + "@" + String(format: "%.4f", resumeAt) }
        var torrent: Torrent
        var resumeAt: Float = 0
    }

    struct SwapPending: Equatable {
        var resumeAt: Float
        var failedURL: String
    }

    var body: some View {
        SelectTorrentQualityButton(media: media, action: { torrent in
            // Fresh play attempt — clear the swap exclusion list so the
            // user gets the full pool again next time the toast fires.
            self.triedURLs = []
            // Defensive — cancel any prefetch streamer that might
            // still be alive from a prior code path. Currently a
            // no-op because `MoviePrefetcher.shared.start(...)`
            // isn't called below, but the cancel is cheap and
            // preserves the invariant if prefetch is re-enabled.
            MoviePrefetcher.shared.cancel()
            self.showTorrent = PlayTorrent(torrent: torrent)
        }, label: {
            VStack {
                VisualEffectBlur() {
                    Image("Play")
                }
                // Label flips to "Resume" when the watchlist holds a
                // saved position for this media — pairs with the auto-
                // resume in PlayerViewModel.playOnAppear so the user
                // knows what tapping is going to do (jump in mid-movie
                // vs start from the beginning).
                Text(hasResumePoint ? "Resume" : "Play")
            }
        })
        .frame(width: theme.buttonWidth, height: theme.buttonHeight)
        .fullScreenContent(item: $showTorrent, title: media.title) { item in
            TorrentPlayerView(
                torrent: item.torrent,
                media: media,
                resumeAt: item.resumeAt,
                onSwitchSource: { resumeAt in
                    handleSwitch(failedURL: item.torrent.url, resumeAt: resumeAt)
                }
            )
        }
        .confirmationDialog(
            "Choose a different source",
            isPresented: $showingSwapPicker,
            titleVisibility: .visible,
            actions: { swapPickerActions },
            message: { Text("The previous source had playback issues. Pick another to continue from where you left off.") }
        )
        // Prefetch invocation disabled — see the comment on the
        // `prefetcher` property declaration. Re-enable by un-
        // commenting the body of this `.task`.
        // .task(id: "\(media.id)-\(media.torrents.count)") {
        //     do { try await Task.sleep(for: .milliseconds(400)) }
        //     catch { return }
        //     MoviePrefetcher.shared.start(media: media)
        // }
    }

    /// Buttons rendered inside the swap picker. Sorted by adjusted
    /// quality score (registry-demoted) so the user's first option is
    /// the next-best after the failed one. Tried URLs are filtered out;
    /// the failed torrent is excluded from this view but still tracked
    /// in `triedURLs` so future swaps don't suggest it again.
    @ViewBuilder
    private var swapPickerActions: some View {
        let candidates = media.torrents
            .filter { !triedURLs.contains($0.url) }
            .sorted(by: { adjustedQualityScore($0) > adjustedQualityScore($1) })

        ForEach(candidates) { torrent in
            Button(swapPickerLabel(for: torrent)) {
                if let pending = swapPending {
                    showTorrent = PlayTorrent(torrent: torrent, resumeAt: pending.resumeAt)
                }
                swapPending = nil
            }
        }
        Button("Cancel", role: .cancel) {
            swapPending = nil
        }
    }

    /// Build a one-line description for a torrent in the swap picker —
    /// quality + source tier + seed count, mirroring the main picker so
    /// the user sees the same information they'd see if they'd opened
    /// the picker manually via long-press on Play.
    private func swapPickerLabel(for torrent: Torrent) -> String {
        let quality = torrent.quality ?? "?"
        let source: String
        switch torrent.releaseSource {
        case .bluray:   source = " · BluRay"
        case .webdl:    source = " · WEB-DL"
        case .webrip:   source = " · WEBRip"
        case .hdtv:     source = " · HDTV"
        case .dvdrip:   source = " · DVDRip"
        case .screener: source = " · CAM"
        case .unknown:  source = ""
        }
        return "\(quality)\(source) (\(torrent.seeds) seeds)"
    }

    /// True when the watchlist has a non-zero saved position for this
    /// media. Mirrors the lookup PreloadTorrentViewModel uses — Movie
    /// vs Episode get different singletons because WatchedlistManager
    /// is generic and namespaces its UserDefaults keys per type.
    private var hasResumePoint: Bool {
        let progress: Float
        if media is Movie {
            progress = WatchedlistManager<Movie>.movie.currentProgress(media.id)
        } else if media is Episode {
            progress = WatchedlistManager<Episode>.episode.currentProgress(media.id)
        } else {
            progress = 0
        }
        return progress > 0
    }

    /// Called from the in-player toast when the user taps "Switch source".
    /// Records the failed URL, dismisses the player, then opens the
    /// swap picker so the user can choose the replacement. We delay the
    /// picker by one runloop tick to let the fullScreenContent dismiss
    /// cleanly — SwiftUI doesn't like dismissing a presentation and
    /// presenting another one in the same frame.
    private func handleSwitch(failedURL: String, resumeAt: Float) {
        triedURLs.insert(failedURL)
        swapPending = SwapPending(resumeAt: resumeAt, failedURL: failedURL)
        showTorrent = nil

        // No alternatives → don't even bother opening the picker.
        let hasAlternatives = media.torrents.contains(where: { !triedURLs.contains($0.url) })
        guard hasAlternatives else {
            swapPending = nil
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showingSwapPicker = true
        }
    }
}

extension PlayButton {
    struct Theme {
        let buttonWidth: CGFloat = value(tvOS: 142, macOS: 100)
        let buttonHeight: CGFloat = value(tvOS: 115, macOS: 81)
    }
}

struct PlayButton_Previews: PreviewProvider {
    static var previews: some View {
        PlayButton(media: Movie.dummy())
            .buttonStyle(TVButtonStyle())
            .padding(40)
            .previewLayout(.fixed(width: 300, height: 300))
            .preferredColorScheme(.dark)
    }
}
