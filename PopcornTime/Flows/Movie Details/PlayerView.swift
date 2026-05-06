//
//  PlayerView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
struct PlayerView: View {
    @EnvironmentObject var viewModel: PlayerViewModel
    @GestureState var isDetectingLongPress = false
    @Environment(\.presentationMode) var presentationMode
    
    @Namespace private var namespace
    @Environment(\.resetFocus) var resetFocus
    
    var body: some View {
        ZStack {
            VLCPlayerView(mediaplayer: viewModel.mediaplayer)
                .focusable(!viewModel.showInfo)
//                .focusable()
                .onPlayPauseCommand(perform: {
                    if viewModel.isLoading {
                        return
                    }
                    viewModel.playandPause()
                })
                .onLongPressGesture(minimumDuration: 0.01, pressing: { _ in }) {
                    if viewModel.isLoading {
                        return
                    }
                    if (viewModel.showControls && viewModel.progress.isScrubbing) {
                        viewModel.clickGesture()
                    }
                    withAnimation {
                        viewModel.toggleControlsVisible()
                    }
                }
                .onMoveCommand(perform: { direction in
                    if viewModel.isLoading {
                        return
                    }
                    
                    switch direction {
                    case .down:
                        withAnimation(.spring()) {
                            viewModel.showInfo = true
                        }
                    case .up:
                        withAnimation(.spring()) {
                            viewModel.showInfo = false
                        }
                    case .left:
                        viewModel.rewind()
                        viewModel.progress.hint = .rewind
                        viewModel.resetIdleTimer()
                    case .right:
                        viewModel.fastForward()
                        viewModel.progress.hint = .fastForward
                        viewModel.resetIdleTimer()
                    @unknown default:
                        break
                    }
                })
                .onExitCommand(perform: {
                    viewModel.stop()
                    presentationMode.wrappedValue.dismiss()
                })
            dimmerView
            overlayView
            
            if viewModel.isLoading {
                ProgressView()
            }
            if viewModel.showInfo {
                VStack {
                    PlayerOptionsView(media: viewModel.media,
                                      audioDelay: viewModel.audioDelayBinding,
                                      audioProfile: viewModel.audioProfileBinding,
                                      subtitleDelay: viewModel.subtitleDelayBinding,
                                      subtitleEncoding: viewModel.subtitleEncodingBinding,
                                      subtitle: viewModel.subtitleBinding
                                      )
//                        .focusable()
//                        .prefersDefaultFocus(in: namespace)
                        .onExitCommand(perform: {
                            withAnimation(.spring()) {
                                viewModel.showInfo = false
                            }
                        })
//                    .frame(alignment: .top)
                    Spacer()
                }
                .transition(.move(edge: .top))
//                .onAppear(perform: {
//                    DispatchQueue.main.async {
//                         self.resetFocus.callAsFunction(in: namespace)
//                    }
//                })
//                .zIndex(1)
            }
        }
        .onAppear {
            viewModel.playOnAppear()
        }.onDisappear {
            
        }
        .focusScope(namespace)
        .ignoresSafeArea()
    }


    @ViewBuilder
    var dimmerView: some View {
        if viewModel.showControls {
            Color(white: 0, opacity: 0.3)
                .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    var overlayView: some View {
        if !viewModel.isLoading && viewModel.showControls {
            VStack {
                if viewModel.showInfo {
                    Image("Now Playing Info")
                        .padding(.top, 40)
                }
                Spacer()
                ZStack {
                    Rectangle()
                        .foregroundColor(.clear)        // Making rectangle transparent
                        .background(LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .top, endPoint: .bottom))
                        .frame(height: 190)
                    ProgressBarView(progress: viewModel.progress)
//                    ProgressView(value: viewModel.progress.progress)
                        .frame(height: 10)
                        .padding([.leading, .trailing], 90)
                }
            }
        }
    }
    
     var longPress: some Gesture {
         LongPressGesture(minimumDuration: 3)
             .updating($isDetectingLongPress) { currentState, gestureState, transaction in
                 gestureState = currentState
             }
     }
}

struct PlayerView_Previews: PreviewProvider {
    static var previews: some View {
        let url = URL(string: "http://www.youtube.com/watch?v=zI2qbr99H64")!
        let loadingModel = PlayerViewModel(media: Movie.dummy(), fromUrl: url, localUrl: url, directory: url, streamer: .shared())
        
        let showControlsModel = PlayerViewModel(media: Movie.dummy(), fromUrl: url, localUrl: url, directory: url, streamer: .shared())
        showControlsModel.isLoading = false
        showControlsModel.showControls = true
        showControlsModel.showInfo = true
        
        
        return Group {
            PlayerView()
                .background(Color.blue)
                .environmentObject(showControlsModel)
            PlayerView()
                .background(Color.blue)
                .environmentObject(loadingModel)
        }
    }
}


