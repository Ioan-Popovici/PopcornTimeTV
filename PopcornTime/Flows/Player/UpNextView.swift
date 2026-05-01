//
//  UpNextView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit

public let ShowUpNextDuration = 30 // seconds

struct UpNextView: View {
    let theme = Theme()
    
    var episode: Episode
    var show: Show
    @ObservedObject var playerModel: PlayerViewModel
    var onPlayNext: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Button {
                playNext()
            } label: {
                episodeView
                    .border(Color.white)
                    .background(Color(white: 0, opacity: 0.9))
            }
            .frame(width: theme.episodeWidth, height: theme.episodeHeight)
            .padding(.bottom, 10)
            .buttonStyle(PlainNavigationLinkButtonStyle())
            
            Button {
                playerModel.progress.showUpNext = false
            } label: {
                Text("Hide")
            }
            .frame(width: theme.episodeWidth, height: 40)
            .background(Capsule(style: .continuous)
                            .foregroundColor(Color(white: 0, opacity: 0.9)))
            .buttonStyle(PlainNavigationLinkButtonStyle())
        }
        .onChange(of: playerModel.progress.showUpNextProgress) { _, newValue in
            let completed = newValue == 0
            if completed {
                playNext()
            }
        }
        .buttonStyle(.plain)
        .accentColor(.white)
    }

    @ViewBuilder
    var episodeView: some View {
        ZStack {
            EpisodeView(episode: episode)
                .environmentObject(ShowDetailsViewModel(show: show))
            Circle()
                .fill(Color.init(white: 0, opacity: 0.5))
                .frame(width: 80, height: 80)
                .overlay {
                    Circle()
                        .trim(from:0, to: playerModel.progress.showUpNextProgress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 4))
                        .animation(.linear(duration: theme.animationDuration), value: playerModel.progress.showUpNextProgress)
                        .rotationEffect(Angle(degrees: -90))
                }
                .overlay {
                    Image("Play")
                        .padding(.leading, 8)
                }
                .padding(.bottom, 40)
            
        }
    }
    
    func playNext() {
        playerModel.dismiss = nil
        playerModel.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onPlayNext()
        }
    }
}

extension UpNextView {
    struct Theme {
        let episodeWidth: CGFloat = value(tvOS: 310, macOS: 217)
        let episodeHeight: CGFloat = value(tvOS: 215, macOS: 150)
        let animationDuration: CGFloat = value(tvOS: 2, macOS: 1)
    }
}

struct UpNextView_Previews: PreviewProvider {
    static var previews: some View {
        let episode = Episode(JSON: showEpisodesJSON[0])!
        
        let url = URL(string: "http://www.youtube.com/watch?v=zI2qbr99H64")!
        let directory = URL(fileURLWithPath: "/tmp")
        let playerModel = PlayerViewModel(media: Movie.dummy(), fromUrl: url, localUrl: directory, directory: directory, streamer: .init())
        playerModel.isLoading = false
        playerModel.showControls = true
        playerModel.showInfo = true
        
        return UpNextView(episode: episode, show: episode.show!, playerModel: playerModel, onPlayNext: { })
            .environmentObject(ShowDetailsViewModel(show: episode.show!))
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .background(.blue)
        
    }
}
