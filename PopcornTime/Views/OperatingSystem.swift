//
//  OperatingSystem.swift
//  PopcornTime
//
//  Created by Alexandru Tudose on 05.08.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
//#if canImport(UIKit)
//import UIKit
//var lastOrientation: UIDeviceOrientation = .unknown
//#endif

private var keyWindowBoundsUnsafe: CGRect {
    #if os(iOS)
    MainActor.assumeIsolated {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds }
            .first ?? .zero
    }
    #else
    .zero
    #endif
}

func value<T>(tvOS: T, macOS: T, compactSize: T? = nil) -> T {
    #if os(tvOS)
        return tvOS
    #elseif os(macOS)
        return macOS
    #elseif os(iOS)

    let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
    if isPhone, let compactSize = compactSize {
        let bounds = keyWindowBoundsUnsafe
        let isPortrait = bounds.width < bounds.height
        return isPortrait ? compactSize : macOS
    } else {
        return macOS
    }
    #endif
}

struct CompactSizeClassModifier: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var sizeClass
    #endif
    
    func body(content: Content) -> some View {
        #if os(iOS)
        
//        let isPortrait = UIScreen.main.bounds.width < UIScreen.main.bounds.height
//        if isPortrait {
        if sizeClass == .compact {
            
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    
    @ViewBuilder
    func hideIfCompactSize() -> some View {
        #if os(iOS)
        let bounds = keyWindowBoundsUnsafe
        let isPortrait = bounds.width < bounds.height
        let isPhone = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .phone }
        if isPhone, isPortrait {

        } else {
            self
        }
        #else
        self
        #endif
    }
    
    @ViewBuilder
    func hideIfPhone() -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            
        } else {
            self
        }
        #else
        self
        #endif
    }
}
