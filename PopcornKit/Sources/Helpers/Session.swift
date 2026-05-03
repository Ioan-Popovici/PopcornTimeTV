//
//  Session.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation

enum Session {

    static var traktCredentials: Data? {
        get { UserDefaults.standard.data(forKey: "traktCredentials") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "traktCredentials") }
            else { UserDefaults.standard.removeObject(forKey: "traktCredentials") }
        }
    }

    static var skipReleaseVersion: Data? {
        get { UserDefaults.standard.data(forKey: "skipReleaseVersion") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "skipReleaseVersion") }
            else { UserDefaults.standard.removeObject(forKey: "skipReleaseVersion") }
        }
    }

    // last valid url
    static var lastPopcornBaseUrl: String? {
        get { UserDefaults.standard.string(forKey: "popcornUrl") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "popcornUrl") }
            else { UserDefaults.standard.removeObject(forKey: "popcornUrl") }
        }
    }

    // urls separated by comma
    static var popcornBaseUrls: String? {
        get { UserDefaults.standard.string(forKey: "popcornUrls") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "popcornUrls") }
            else { UserDefaults.standard.removeObject(forKey: "popcornUrls") }
        }
    }
}
