//
//  SecondaryScreen.swift
//  PopcornTime
//
//  Created by Alexandru Tudose on 04.10.2022.
//  Copyright © 2022 PopcornTime. All rights reserved.
//

import SwiftUI
import Combine

@MainActor
final class ExternalDisplayContent: ObservableObject {
    @Published var view: AnyView?
    var isShowingOnExternalDisplay = false
}

/// Observer when a new display is connected.
///
/// iOS 16+ replaces UIScreen.didConnect/didDisconnectNotification with the
/// UIScene scene-tracking notifications below. We watch UIWindowScene
/// connect/disconnect events, then attach an ExternalView to any newly
/// available external screen.
struct SecondaryScreen: ViewModifier {
    @State var additionalWindows: [UIWindow] = []
    @StateObject var displayContent = ExternalDisplayContent()

    private var sceneDidConnectPublisher: AnyPublisher<UIWindowScene, Never> {
        NotificationCenter.default
            .publisher(for: UIScene.willConnectNotification)
            .compactMap { $0.object as? UIWindowScene }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    private var sceneDidDisconnectPublisher: AnyPublisher<UIWindowScene, Never> {
        NotificationCenter.default
            .publisher(for: UIScene.didDisconnectNotification)
            .compactMap { $0.object as? UIWindowScene }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }

    func body(content: Content) -> some View {
        content
            .environmentObject(displayContent)
            .onReceive(sceneDidConnectPublisher, perform: sceneDidConnect)
            .onReceive(sceneDidDisconnectPublisher, perform: sceneDidDisconnect)
    }

    private func sceneDidDisconnect(_ scene: UIWindowScene) {
        additionalWindows.removeAll { $0.windowScene === scene }
        displayContent.isShowingOnExternalDisplay = false
    }

    private func sceneDidConnect(_ scene: UIWindowScene) {
        // Only attach to non-key (i.e. external) scenes
        let keyScene = UIApplication.shared.connectedScenes
            .first { ($0 as? UIWindowScene)?.keyWindow != nil } as? UIWindowScene
        guard scene !== keyScene else { return }

        let screen = scene.screen
        let window = UIWindow(windowScene: scene)
        window.frame = screen.bounds

        screen.overscanCompensation = .scale

        let view = ExternalView(screen: screen)
            .environmentObject(displayContent)
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        controller.view.bounds = screen.bounds
        controller.view.backgroundColor = UIColor.red
        window.isHidden = false
        additionalWindows.append(window)

        displayContent.isShowingOnExternalDisplay = true
    }
}
