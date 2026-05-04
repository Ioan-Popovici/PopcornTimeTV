//
//  PlayerAudioController.swift
//  PlayerAudioController
//
//  Created by Alexandru Tudose on 26.08.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation
import SwiftUI
#if os(tvOS)
@preconcurrency import TVVLCKit
#elseif os(iOS)
@preconcurrency import MobileVLCKit
#elseif os(macOS)
@preconcurrency import VLCKit
#endif
import AVKit

@MainActor
class PlayerAudioModel {
    private(set) var mediaplayer: VLCMediaPlayer
    var audioProfile: EqualizerProfiles = .fullDynamicRange
    var audioProfileBinding: Binding<EqualizerProfiles> = .constant(.fullDynamicRange)
    var audioDelayBinding: Binding<Int> = .constant(0)
    
    var audioTracksNames: () -> [String] = { return [] }
    var audioTrackBinding: Binding<Int> = .constant(0)
    
    init(mediaplayer: VLCMediaPlayer) {
        self.mediaplayer = mediaplayer
        mediaplayer.currentAudioPlaybackDelay = 0
        audioTracksNames = { mediaplayer.audioTrackNames.map({ $0 as! String }) }
        
        audioDelayBinding = Binding(get: {
            mediaplayer.currentAudioPlaybackDelay / 1_000_000 // from microseconds to seconds
        }, set: { newDelay in
            mediaplayer.currentAudioPlaybackDelay = newDelay * 1_000_000
        })
        
        audioProfileBinding = Binding(get: { [unowned self] in
            return audioProfile
        }, set: { [unowned self] profile in
            audioProfile = profile
            didSelectEqualizerProfile(profile)
        })
        
        audioTrackBinding = Binding(get: {
            return Int(mediaplayer.currentAudioTrackIndex)
        }, set: { trackIndex in
            mediaplayer.currentAudioTrackIndex = Int32(trackIndex)
        })
        
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        didSelectEqualizerProfile(.fullDynamicRange)
        #endif
    }
    
    func didSelectEqualizerProfile(_ profile: EqualizerProfiles) {
        let equalizer = VLCAudioEqualizer(preset: VLCAudioEqualizer.presets[Int(profile.rawValue)])
        mediaplayer.equalizer = equalizer
    }

    /// Find the audio track inside the now-playing media that best matches
    /// the user's `Session.preferredAudioLanguage` and switch to it. Called
    /// by PlayerViewModel once VLC reports the first time-changed event
    /// (which is when track metadata becomes available).
    ///
    /// VLC track names come from the container metadata: usually the ISO
    /// 639 code or the language's English name (`"English"`, `"Russian"`,
    /// `"eng"`, `"rus"`, `"und"`, …). We compare against the ISO code and
    /// the language name in both English *and* the system locale, so a
    /// macOS in Russian still matches an "English" track tag and vice
    /// versa.
    func selectPreferredAudioTrack(language: String) {
        let normalized = language.lowercased()
        guard !normalized.isEmpty else { return }

        // Build a list of candidate strings the matching track name might
        // contain (case-insensitive substring match).
        var candidates: Set<String> = [normalized]
        if let englishName = Locale(identifier: "en").localizedString(forLanguageCode: normalized) {
            candidates.insert(englishName.lowercased())
        }
        if let localized = Locale.current.localizedString(forLanguageCode: normalized) {
            candidates.insert(localized.lowercased())
        }
        // ISO 639-2/B three-letter forms VLC commonly emits.
        candidates.formUnion(Self.iso639Codes(for: normalized))

        let names = audioTracksNames()
        for (i, name) in names.enumerated() {
            let lower = name.lowercased()
            if candidates.contains(where: { lower.contains($0) }) {
                mediaplayer.currentAudioTrackIndex = Int32(i)
                #if DEBUG
                print("[Audio] selected track #\(i) '\(name)' for preferred='\(language)'")
                #endif
                return
            }
        }
        #if DEBUG
        print("[Audio] no track matched preferred='\(language)' in \(names)")
        #endif
    }

    /// Map of ISO 639-1 → 639-2/B (the form VLC tends to emit). Just the
    /// commonly-released languages — not exhaustive, falls through cleanly.
    private static func iso639Codes(for code: String) -> Set<String> {
        switch code {
        case "en": return ["eng"]
        case "ru": return ["rus"]
        case "uk": return ["ukr"]
        case "fr": return ["fra", "fre"]
        case "de": return ["ger", "deu"]
        case "es": return ["spa"]
        case "it": return ["ita"]
        case "pt": return ["por"]
        case "ja": return ["jpn"]
        case "ko": return ["kor"]
        case "zh": return ["zho", "chi"]
        case "ar": return ["ara"]
        case "tr": return ["tur"]
        case "pl": return ["pol"]
        case "nl": return ["nld", "dut"]
        case "fi": return ["fin"]
        case "sv": return ["swe"]
        case "no": return ["nor"]
        case "da": return ["dan"]
        case "cs": return ["ces", "cze"]
        case "el": return ["ell", "gre"]
        case "he": return ["heb"]
        case "hi": return ["hin"]
        case "id": return ["ind"]
        case "ms": return ["msa", "may"]
        case "ro": return ["ron", "rum"]
        case "sk": return ["slk", "slo"]
        case "sl": return ["slv"]
        case "th": return ["tha"]
        case "vi": return ["vie"]
        case "hu": return ["hun"]
        case "ca": return ["cat"]
        case "hr": return ["hrv"]
        case "sr": return ["srp"]
        case "bs": return ["bos"]
        default: return []
        }
    }
}
