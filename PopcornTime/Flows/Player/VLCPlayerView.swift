//
//  VLCPlayerView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 21.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
#if os(tvOS)
import TVVLCKit
typealias VLCPlayerView = VLCPlayerView_tvOS
#elseif os(iOS)
import MobileVLCKit
typealias VLCPlayerView = ExternalDisplayWrapper
#elseif os(macOS)
import VLCKit
typealias VLCPlayerView = VLCPlayerView_MACWrapper
#endif


#if os(macOS)

struct VLCPlayerView_MACWrapper: View {
    var mediaplayer: VLCMediaPlayer
    @State var disableScreenSaverToken: NSObjectProtocol?
    
    var body: some View {
        VLCPlayerView_MAC(mediaplayer: mediaplayer)
            .onAppear {
                disableScreenSaverToken = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "disable screen saver")
                NSCursor.setHiddenUntilMouseMoves(true)
            }
            .onDisappear {
                if let token = disableScreenSaverToken {
                    ProcessInfo.processInfo.endActivity(token)
                    disableScreenSaverToken = nil
                }
            }
    }
}

struct VLCPlayerView_MAC: NSViewRepresentable {
    var mediaplayer = VLCMediaPlayer()
    
    ///https://code.videolan.org/videolan/vlc/-/issues/25264
    @State var fixedFirstTimeInvalidSize = false
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Re-enabled. Workaround for VLCKit bug 25264: on first
        // launch the drawable's size is reported as 0×0 to libvlc, so
        // the video output renders to a black surface even though
        // VLC is decoding pieces and requesting bytes from
        // `GCDWebServer`. Bumping the window height by +1 / −1 px
        // forces VLC to re-query the drawable size and bind the
        // video layer correctly. Was commented out at some point and
        // is the most likely cause of the "black screen but pieces
        // are downloading" symptom currently observed.
        fixFirstTimeInvalidSize(view: view)
        return view
    }
    
    func updateNSView(_ view: NSView, context: Context) {
        mediaplayer.drawable = view
    }
    
    func fixFirstTimeInvalidSize(view: NSView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
            if !fixedFirstTimeInvalidSize && !mediaplayer.hasVideoOut {
                fixFirstTimeInvalidSize(view: view) // delay
                return
            }
            
            if !fixedFirstTimeInvalidSize, var frame = view.window?.frame {
                frame.size.height += 1
                view.window?.setFrame(frame, display: true)
                fixedFirstTimeInvalidSize = true
                // revert back
                DispatchQueue.main.async {
                    frame.size.height -= 1
                    view.window?.setFrame(frame, display: true)
                }
            }
        }
    }
}
#endif

#if os(iOS)
/// Show videoplayer on external monitor when is connected trough usb-c port
struct ExternalDisplayWrapper: View {
    var mediaplayer = VLCMediaPlayer()
    
    var body: some View {
        SecondaryScreenDisplay {
            VLCPlayerView_iOS(mediaplayer: mediaplayer)
        }
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea()
    }
}

struct VLCPlayerView_iOS: UIViewRepresentable {
    var mediaplayer = VLCMediaPlayer()
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        mediaplayer.drawable = view
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        mediaplayer.drawable = uiView
    }
}
#endif


#if os(tvOS)
struct VLCPlayerView_tvOS: UIViewRepresentable {
    var mediaplayer = VLCMediaPlayer()
    
    var onSwipeUp: (() -> Void)?
    var onSwipeDown: (() -> Void)?
    var onPositionSliderDrag: ((Float) -> Void)?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        mediaplayer.drawable = view
        context.coordinator.addGestures(view: view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        mediaplayer.drawable = uiView
    }
    
    func makeCoordinator() -> VLCPlayerCoordinator {
        let coordinator = VLCPlayerCoordinator()
        coordinator.onSwipeDown = onSwipeDown
        coordinator.onSwipeUp = onSwipeUp
        coordinator.onPositionSliderDrag = onPositionSliderDrag
        return coordinator
    }
    
    class VLCPlayerCoordinator: NSObject, UIGestureRecognizerDelegate {
        var onSwipeUp: (() -> Void)?
        var onSwipeDown: (() -> Void)?
        var onPositionSliderDrag: ((Float) -> Void)?

        var lastTranslation: CGFloat = .zero
        var progressBarWidth: CGFloat = 1000.0
        
        func addGestures(view: UIView) {
            let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipeDownGesture))
            swipeDownGesture.direction = .down
            swipeDownGesture.cancelsTouchesInView = false
            swipeDownGesture.delegate = self
            view.addGestureRecognizer(swipeDownGesture)
            
//            let swipeUpGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipeUpGesture))
//            swipeUpGesture.direction = .up
//            swipeUpGesture.delegate = self
//            view.addGestureRecognizer(swipeUpGesture)
            
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(onPanGestureAction(gesture:)))
            view.addGestureRecognizer(panGesture)
        }
        
        @objc func swipeUpGesture() {
            onSwipeUp?()
        }
        
        @objc func swipeDownGesture() {
            onSwipeDown?()
        }
        
        @objc func onPanGestureAction(gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let offset = Float((translation.x - lastTranslation) / progressBarWidth / 8.0)
            
            switch gesture.state {
            case .cancelled:
                fallthrough
            case .ended:
                lastTranslation = 0.0
            case .began:
                fallthrough
            case .changed:
                onPositionSliderDrag?(offset)
                lastTranslation = translation.x
            default:
                return
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}
#endif

#if os(tvOS)
extension VLCPlayerView_tvOS {
    
    func addGestures(onSwipeDown: @escaping () -> Void,
                     onSwipeUp: @escaping () -> Void,
                     onPositionSliderDrag: @escaping (Float) -> Void) -> Self {

        return Self.init(mediaplayer: mediaplayer, onSwipeUp: onSwipeUp, onSwipeDown: onSwipeDown, onPositionSliderDrag: onPositionSliderDrag)
    }
}

#endif
