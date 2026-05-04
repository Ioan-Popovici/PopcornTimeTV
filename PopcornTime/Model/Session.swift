//
//  Session.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation

private extension UserDefaults {
    func optionalString(forKey key: String) -> String? { string(forKey: key) }
    func optionalData(forKey key: String) -> Data? { data(forKey: key) }
    func optionalDate(forKey key: String) -> Date? { object(forKey: key) as? Date }
}

enum Session {
    static var tosAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: "tosAccepted") }
        set { UserDefaults.standard.set(newValue, forKey: "tosAccepted") }
    }

    static var autoSelectQuality: String? {
        get { UserDefaults.standard.optionalString(forKey: "autoSelectQuality") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "autoSelectQuality") }
            else { UserDefaults.standard.removeObject(forKey: "autoSelectQuality") }
        }
    }

    /// Preferred audio language for torrent selection (ISO 639-1, e.g. "en",
    /// "ru", "ua"). Defaults to the system language so users on a Russian
    /// macOS get RU torrents auto-selected. Set to "" to disable preference
    /// and treat every locale equally.
    static var preferredAudioLanguage: String {
        get {
            if let stored = UserDefaults.standard.optionalString(forKey: "preferredAudioLanguage") {
                return stored
            }
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferredAudioLanguage")
        }
    }

    static var streamOnCellular: Bool {
        get { UserDefaults.standard.bool(forKey: "streamOnCellular") }
        set { UserDefaults.standard.set(newValue, forKey: "streamOnCellular") }
    }

    static var removeCacheOnPlayerExit: Bool {
        get { UserDefaults.standard.bool(forKey: "removeCacheOnPlayerExit") }
        set { UserDefaults.standard.set(newValue, forKey: "removeCacheOnPlayerExit") }
    }

    static var themeSongVolume: Float {
        get {
            let raw = UserDefaults.standard.object(forKey: "themeSongVolume") as? Float
            return raw ?? 0.75
        }
        set { UserDefaults.standard.set(newValue, forKey: "themeSongVolume") }
    }

    static var oauthCredentials: Data? {
        get { UserDefaults.standard.optionalData(forKey: "oauthCredentials") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "oauthCredentials") }
            else { UserDefaults.standard.removeObject(forKey: "oauthCredentials") }
        }
    }

    static var skipReleaseVersion: Data? {
        get { UserDefaults.standard.optionalData(forKey: "skipReleaseVersion") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "skipReleaseVersion") }
            else { UserDefaults.standard.removeObject(forKey: "skipReleaseVersion") }
        }
    }

    static var subtitleSettings: Data? {
        get { UserDefaults.standard.optionalData(forKey: "subtitleSettings") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "subtitleSettings") }
            else { UserDefaults.standard.removeObject(forKey: "subtitleSettings") }
        }
    }

    static var lastVersionCheckPerformedOnDate: Date? {
        get { UserDefaults.standard.optionalDate(forKey: "lastVersionCheckPerformedOnDate") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "lastVersionCheckPerformedOnDate") }
            else { UserDefaults.standard.removeObject(forKey: "lastVersionCheckPerformedOnDate") }
        }
    }
}
