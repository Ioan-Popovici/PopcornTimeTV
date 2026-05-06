//
//  PreloadTorrentView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
import Kingfisher

struct PreloadTorrentView: View {
    @StateObject var viewModel: PreloadTorrentViewModel
    @Environment(\.dismiss) var dismiss
    /// Live mirror of `Session.showStreamingDetails`. When `false` the
    /// detailed bar + stats panel is replaced by a centered spinner.
    @AppStorage("showStreamingDetails") private var showStreamingDetails = true
    
    var body: some View {
        ZStack {
            // Blurred backdrop image — matches popcorn-desktop's
            // `loading-backdrop` (the full-screen blurred poster
            // behind everything). Falls back to plain black for
            // entries without a backdrop in the API payload.
            backdropLayer
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()
                Text(viewModel.media.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)

                progressView

                // Inline "Switch source" link — combines two prompts:
                //   - the 10-second "Taking a while?" timeout if the
                //     stream hasn't progressed but the health monitor
                //     hasn't fired anything (cold-start grace is 30s).
                //   - the actual issue text once the health monitor
                //     surfaces something (peerCollapse / bufferStall /
                //     etc.). Same Switch action, different lead text.
                if let prompt = swapPromptMessage {
                    swapPrompt(message: prompt)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                #if os(iOS)
                cancelButton
                    .padding(.top, 12)
                #endif
                Spacer()
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 20)
            .onAppear {
                viewModel.playTorrent()
            }.onDisappear {
                viewModel.cancel()
            }
            .alert(isPresented: $viewModel.showError, content: {
                errorAlert
            })
            #if os(iOS) || os(tvOS)
            .confirmationDialog("Select file to play", isPresented: $viewModel.showFileToPlay, titleVisibility: .visible, actions: {
                chooseFilesButtons(fileNames: viewModel.filesToPlay)
            })
            #elseif os(macOS)
            .popover(isPresented: $viewModel.showFileToPlay, content: {
                VStack {
                    Text("Select file to play")
                    chooseFilesButtons(fileNames: viewModel.filesToPlay)
                        .controlSize(.large)
                }
                .font(.system(size: 16))
                .padding(20)
            })
            #endif
        }
        .animation(.spring(), value: viewModel.healthIssue)
        .accentColor(.white)
    }

    /// Full-screen blurred backdrop image (movie / show poster) with a
    /// dark overlay — matches the `loading-backdrop` + `loading-backdrop-overlay`
    /// pair from popcorn-desktop's `loading.tpl`.
    @ViewBuilder
    var backdropLayer: some View {
        ZStack {
            Color.black
            if let urlString = viewModel.media.largeBackgroundImage ?? viewModel.media.mediumBackgroundImage,
               !urlString.isEmpty,
               let url = URL(string: urlString) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 20)
                    .clipped()
                    .opacity(0.7)  // matches desktop's brightness(0.7)
                Color.black.opacity(0.65)
            }
        }
    }

    /// Determinate linear progress bar + status line + stats panel.
    /// The bar value is the streamer's monotonic "ready to play"
    /// signal (`bufferingProgress`, latched to 1.0 by the streamer
    /// once the initial head-piece batch is on disk). Apple HIG: use
    /// a determinate progress bar whenever a measurable value exists;
    /// reserve the indeterminate spinner for genuinely unknown work.
    ///
    /// When `Session.showStreamingDetails` is off, the entire bar +
    /// stats panel is replaced by a centered indeterminate circular
    /// spinner — quieter loading UI for users who don't want the
    /// technical readout.
    @ViewBuilder
    var progressView: some View {
        if showStreamingDetails {
            VStack(spacing: 12) {
                ProgressView(value: viewModel.progress)
                    .progressViewStyle(.linear)
                    .tint(.white)

                Text(displayStatus)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    #if os(tvOS)
                    .font(.system(size: 26, weight: .regular))
                    #else
                    .font(.system(size: 13, weight: .regular))
                    #endif

                statsPanel
            }
        } else {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                #if os(tvOS)
                .scaleEffect(2)
                #else
                .scaleEffect(1.5)
                #endif
                .padding(.vertical, 8)
        }
    }

    /// Compact rounded panel with download rate, peers, and how much
    /// of the file is on disk. The "ready to play" indicator IS the
    /// progress bar above — duplicating it here would just be noisy.
    /// "Downloaded" tracks `totalProgress` (fraction of the selected
    /// file written to disk), which is what users care about for
    /// seek-back behaviour: the higher this number, the more of the
    /// movie is locally available without re-fetching.
    @ViewBuilder
    var statsPanel: some View {
        if viewModel.speed > 0 || viewModel.seeds > 0 || viewModel.progress > 0 {
            let downloadedPct = max(0, min(100, Int(round(viewModel.totalProgress * 100))))
            let rate = ByteCountFormatter.string(fromByteCount: Int64(viewModel.speed), countStyle: .binary)
            VStack(spacing: 6) {
                statsRow(label: "Downloaded", value: "\(downloadedPct)%")
                statsRow(label: "Download", value: "\(rate)/s")
                statsRow(label: "Peers", value: "\(viewModel.seeds)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.6))
            )
            .frame(maxWidth: 360)
        }
    }

    @ViewBuilder
    private func statsRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .monospacedDigit()
        }
        #if os(tvOS)
        .font(.system(size: 22, weight: .regular))
        #else
        .font(.system(size: 12, weight: .regular))
        #endif
    }
    
    /// Status line shown above the stats panel. "Connecting to
    /// source…" until libtorrent fires its first non-zero progress
    /// callback; "Downloading…" thereafter. The streamer fires
    /// `readyToPlay` the moment it has the head pieces on disk, so
    /// this view dismisses the moment that happens — there is no
    /// post-ready waiting state to message.
    private var displayStatus: String {
        if viewModel.speed > 0 {
            return "Downloading…".localized
        }
        return "Connecting to source…".localized
    }

    /// Lead-text for the inline swap prompt. Returns the
    /// health-monitor's issue message when one is current, falling
    /// back to the 30-second "Taking a while?" copy. `nil` while
    /// neither has fired so the prompt row is hidden entirely (no
    /// "swap source" link cluttering the view during normal start-up).
    private var swapPromptMessage: String? {
        if let issue = viewModel.healthIssue {
            return issue.localizedMessage
        }
        if viewModel.showSwitchSourcePrompt {
            return "Taking a while?".localized
        }
        return nil
    }

    /// Inline manual swap shortcut: a small grey hint plus a tappable
    /// "Switch source" link. Same chain as the (removed) toast's
    /// Switch button — tears down the current streamer and asks the
    /// parent to pick a replacement; resume stays at 0 since
    /// playback hasn't started.
    @ViewBuilder
    func swapPrompt(message: String) -> some View {
        HStack(spacing: 6) {
            Text(message)
                .foregroundColor(.white.opacity(0.7))
            Button(action: { viewModel.requestSwitchSource() }) {
                Text("Switch source")
                    .foregroundColor(.white)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        #if os(tvOS)
        .font(.system(size: 22))
        #else
        .font(.system(size: 12))
        #endif
        .padding(.top, 4)
    }

    @ViewBuilder
    var cancelButton: some View {
        Button {
            withAnimation {
                dismiss()
            }
        } label: {
            Text("CANCEL")
                .foregroundColor(.blue)
        }

    }
    
    var errorAlert: Alert {
        if viewModel.isNotEnoughSpaceError {
            return Alert(title: Text("Error"),
                         message: Text(viewModel.error?.localizedDescription ?? ""),
                         primaryButton: .default(Text("Clear All Cache"), action: {
                            // Force the failed streamer to drop its data
                            // before the global wipe. Otherwise libtorrent
                            // can keep open file handles to per-torrent
                            // bytes the global emptyCache unlinked,
                            // delaying the kernel from actually freeing
                            // those bytes — so the immediate retry hits
                            // the same `availableSpace` check and fails.
                            viewModel.streamer?.cancelStreamingAndDeleteData(true)
                            viewModel.streamer = nil
                            viewModel.clearCache.emptyCache()
                            viewModel.error = nil
                            viewModel.playTorrent()
                        }),
                         secondaryButton: .cancel(Text("Cancel"), action: {
                            dismiss()
                        })
            )
        } else {
            return Alert(title: Text("Error"),
                  message: Text(viewModel.error?.localizedDescription ?? ""),
                  dismissButton: .cancel(Text("Cancel"), action: {
                    dismiss()
                  }))
        }
    }
    
    @ViewBuilder
    func chooseFilesButtons(fileNames: [String]) -> some View  {
        ForEach(fileNames, id: \.self) { fileName in
            Button {
                viewModel.selectedFileToPlay = fileName
                viewModel.showFileToPlay = false
            } label: {
                Text(fileName)
                #if os(macOS)
                Spacer()
                #endif
            }
        }
    }
}

/// Compact transient banner used over `PlayerView` when the
/// `PlaybackHealthMonitor` surfaces a runtime issue (buffer stall,
/// peer collapse, etc.). Slides in from the top, persists ~8 s
/// (caller-driven via `.task` timeout), and dismisses itself unless
/// the user taps `actionTitle` first. Apple's pattern for transient
/// status info during media playback — TV.app uses essentially this
/// shape for AirPlay events; iOS Mail uses it for "Sent". Single
/// action button, no dedicated dismiss control (banner expires on
/// its own; tapping the action commits).
struct PlaybackBanner: View {
    let message: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .font(.system(size: 13, weight: .regular))
            Spacer(minLength: 8)
            Button(action: onAction) {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

struct PreloadTorrentView_Previews: PreviewProvider {
    static var previews: some View {
        let model = PreloadTorrentViewModel(torrent: Torrent(), media: Movie.dummy(), onReadyToPlay: {_ in })
        PreloadTorrentView(viewModel: model)
            .preferredColorScheme(.dark)
        
        PreloadTorrentView(viewModel: progressModel)
            .preferredColorScheme(.dark)
    }
    
    static var progressModel: PreloadTorrentViewModel {
        let progressModel = PreloadTorrentViewModel(torrent: Torrent(), media: Movie.dummy(), onReadyToPlay: {_ in })
        progressModel.progress = 0.4
        progressModel.speed = 20000
        progressModel.seeds = 10
        progressModel.isProcessing = false
        return progressModel
    }
}
