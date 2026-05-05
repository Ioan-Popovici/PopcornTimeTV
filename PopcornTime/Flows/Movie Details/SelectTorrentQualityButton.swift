//
//  SelectTorrentQualityAction.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 24.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
import Network

let networkMonitor = NWPathMonitor()

/// `Torrent.qualityScore` with the playback-failure registry penalty
/// applied — used by Best ranking and by source-swap fallback so a
/// recently-failed torrent doesn't get re-picked as the replacement.
@MainActor
func adjustedQualityScore(_ torrent: Torrent) -> Int {
    return torrent.qualityScore - PlaybackFailureRegistry.shared.qualityPenalty(url: torrent.url)
}

struct SelectTorrentQualityButton<Label>: View where Label : View {
    var media: Media
    var action: (Torrent) -> Void
    @ViewBuilder var label: () -> Label
    
    struct AlertType: Identifiable {
        enum Choice {
            case noTorrentsFound, streamOnCellular, audioLanguageMissing
        }

        var id: Choice
        var languageDisplay: String?
    }


    @State var showChooseQualityActionSheet = false
    @State var alert: AlertType?
    /// Set when the user dismisses the "no torrents in your language" alert
    /// — proceeds with playback against the full unfiltered list.
    @State var fallbackToAnyLanguage = false
    /// Optional one-line explanation rendered above the picker when the
    /// quality floor pushes us out of the auto-play path (e.g. all sources
    /// are screeners). `nil` when the picker is shown without context
    /// (Off / single-torrent shortcut).
    @State var pickerMessage: String?

    var body: some View {
        return Button(action: {
            if !Session.streamOnCellular && networkMonitor.currentPath.isExpensive {
                alert = .init(id: .streamOnCellular)
                return
            }

            if media.torrents.count == 0 {
                alert = .init(id: .noTorrentsFound)
            } else if !fallbackToAnyLanguage,
                      let preferred = preferredLanguageFilter,
                      preferredLanguageTorrents.isEmpty {
                let display = (Locale.current.localizedString(forLanguageCode: preferred) ?? preferred).capitalized
                alert = .init(id: .audioLanguageMissing, languageDisplay: display)
            } else {
                startPlayback()
            }
        }, label: label)
        // Long-press (iOS / tvOS) or secondary-click (macOS) on the Play
        // button always shows the picker, even when auto-play would have
        // fired — power-user shortcut for "I want to see all the sources
        // before committing." Single tap still auto-plays per Settings.
        .contextMenu {
            Button("Choose Quality…") {
                pickerMessage = nil
                showChooseQualityActionSheet = true
            }
            .disabled(media.torrents.isEmpty)
        }
        #if os(iOS) || os(tvOS)
        .confirmationDialog(
            "Choose Quality",
            isPresented: $showChooseQualityActionSheet,
            titleVisibility: .visible,
            actions: { chooseTorrentsButtons },
            message: { if let pickerMessage { Text(pickerMessage) } }
        )
        #elseif os(macOS)
        .popover(isPresented: $showChooseQualityActionSheet, content: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose Quality")
                if let pickerMessage {
                    Text(pickerMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                chooseTorrentsButtons
                    .controlSize(.large)
            }
            .font(.system(size: 16))
            .padding(20)
        })
        #endif
        .alert(item: $alert) { alert in
            switch alert.id {
            case .noTorrentsFound:
                return Alert(title: Text("No torrents found"),
                      message: Text("Torrents could not be found for the specified media."))
            case .streamOnCellular:
                return Alert(title: Text("Cellular Data is turned off for streaming"),
                      message: nil,
                      primaryButton: .default(Text("Turn On")) {
                        Session.streamOnCellular = true
                      },
                      secondaryButton: .cancel())
            case .audioLanguageMissing:
                let lang = alert.languageDisplay ?? "your preferred language"
                return Alert(
                    title: Text("No \(lang) audio available"),
                    message: Text("No torrents in \(lang) were found for this title. Continue with another language?"),
                    primaryButton: .default(Text("Continue")) {
                        fallbackToAnyLanguage = true
                        // Re-run the selection flow against the full list.
                        startPlayback()
                    },
                    secondaryButton: .cancel()
                )
            }

        }
        .onAppear {
            if networkMonitor.queue == nil {
                networkMonitor.start(queue: .global())
            }
        }
    }

    /// User's preferred audio language; `nil` means "no preference, use any".
    private var preferredLanguageFilter: String? {
        let raw = Session.preferredAudioLanguage
        return raw.isEmpty ? nil : raw
    }

    /// Torrents whose inferred audio tracks include the preferred language.
    /// We use `Torrent.audioLanguages` (locale tag + heuristic title parsing
    /// of Russian-scene release markers) rather than the bare `locale`,
    /// because a popcorn-api `contentLocale=ru` torrent very often carries
    /// the English original audio underneath the Russian voiceover (titles
    /// containing `L`, `MVO`, `Sub`, etc.).
    private var preferredLanguageTorrents: [Torrent] {
        guard let preferred = preferredLanguageFilter?.lowercased() else { return media.torrents }
        return media.torrents.filter { $0.audioLanguages.contains(preferred) }
    }

    /// Pool to draw from when picking / showing torrents — respects the
    /// user's audio-language preference unless they've fallen back via the
    /// "no torrents in your language" alert.
    private var selectableTorrents: [Torrent] {
        if fallbackToAnyLanguage { return media.torrents }
        let filtered = preferredLanguageTorrents
        return filtered.isEmpty ? media.torrents : filtered
    }

    /// One torrent per quality bucket — the variant with the best composite
    /// `qualityScore` (encoding source tier > resolution > seed count, with
    /// theatrical screeners demoted below every other source). Picks
    /// non-screeners over screeners even when the screener has more seeds.
    /// If a bucket has nothing but screeners, we still pick the best of
    /// those rather than silently hiding the quality.
    private var collapsedSelectableTorrents: [Torrent] {
        var byQuality: [String: Torrent] = [:]
        for torrent in selectableTorrents {
            let key = torrent.quality ?? "0p"
            if let existing = byQuality[key], existing.qualityScore >= torrent.qualityScore { continue }
            byQuality[key] = torrent
        }
        return Array(byQuality.values).sorted(by: <)
    }

    /// Decide whether to auto-play the chosen torrent or surface the
    /// picker. The picker only shows when the user explicitly picked
    /// `Selectable` — in any auto mode (Optimal / Highest / Normal),
    /// `autoSelectTorrent` returns a real torrent and we play it.
    /// Floor warnings (`qualityFloorReason`) are still computed and
    /// passed to the picker title when it does show, but they no
    /// longer second-guess the auto-pick — Optimal in particular
    /// correctly prefers a 480p BluRay over a 720p WEB-DL because
    /// source tier dominates resolution in `qualityScore`, and the
    /// old "below 720p" gate was overriding that with a false alarm.
    private func startPlayback() {
        if let torrent = autoSelectTorrent {
            action(torrent)
        } else {
            pickerMessage = qualityFloorReason
            showChooseQualityActionSheet = true
        }
    }

    /// Localised explanation when the quality floor blocks auto-play, or
    /// `nil` when the floor is met. Surfaces the picker even when the user
    /// asked to auto-play — they should know they're committing to a
    /// camcorder rip / dead swarm / sub-720p source when better options
    /// exist or when nothing better exists.
    private var qualityFloorReason: String? {
        let pool = collapsedSelectableTorrents
        guard !pool.isEmpty else { return nil }

        if pool.allSatisfy({ $0.releaseSource == .screener }) {
            return "All available sources are camcorder rips — quality may be poor.".localized
        }
        if pool.allSatisfy({ $0.seeds < 5 }) {
            return "Only low-seed sources available — playback may stall.".localized
        }
        if let pick = autoSelectTorrent,
           Self.resolutionRank(pick.quality) < 30,
           pool.contains(where: { Self.resolutionRank($0.quality) >= 30 }) {
            return "Auto-pick is below 720p — pick manually for higher quality.".localized
        }
        return nil
    }

    /// Numeric resolution rank used by the quality-floor checks. Mirrors
    /// the resolution component of `Torrent.qualityScore` but exposes it
    /// alone so we can compare resolutions without source/seed weighting.
    private static func resolutionRank(_ quality: String?) -> Int {
        switch (quality ?? "").lowercased() {
        case "2160p", "4k": return 50
        case "1080p":       return 40
        case "720p":        return 30
        case "480p":        return 20
        case "3d":          return 10
        default:            return 0
        }
    }

    var autoSelectTorrent: Torrent? {
        let pool = collapsedSelectableTorrents
        guard !pool.isEmpty else { return nil }

        // `pool` is sorted by Torrent's Comparable (resolution-string-length
        // proxy: 3D < 480p < 720p < 1080p < 2160p). So `.first` is the
        // lowest resolution and `.last` is the highest. "Optimal" instead
        // ranks across the pool by composite `qualityScore` — source tier
        // dominates resolution and seeds, so a 1080p BluRay outranks a
        // 2160p HEVC encode of unknown source. We also demote sources
        // that have recently failed playback so the user isn't pushed
        // back onto a known-bad swarm.
        switch Session.autoSelectQuality {
        case "Highest":
            return pool.last
        case "Normal":
            return pool.first
        case "Optimal":
            return pool.max(by: { adjustedQualityScore($0) < adjustedQualityScore($1) })
        case "Selectable":
            break
        default:
            return pool.max(by: { adjustedQualityScore($0) < adjustedQualityScore($1) })
        }

        #if os(tvOS)
        if pool.count == 1 {
            return pool[0]
        }
        #endif

        return nil
    }

    /// Set when the user has expanded the picker via the "Show all sources"
    /// row to access release-level granularity (e.g. picking the Sub variant
    /// over the L variant of the same 1080p release).
    @State var showAllSources = false

    @ViewBuilder
    var chooseTorrentsButtons: some View {
        let collapsedRows = collapsedSelectableTorrents.sorted(by: >)
        let collapsedURLs = Set(collapsedRows.map(\.url))
        let extraRows = selectableTorrents.filter { !collapsedURLs.contains($0.url) }.sorted(by: >)

        ForEach(collapsedRows) { torrent in
            torrentRow(torrent)
        }

        if !extraRows.isEmpty {
            if showAllSources {
                ForEach(extraRows) { torrent in
                    torrentRow(torrent)
                }
            } else {
                Button("Show all sources… (\(extraRows.count) more)") {
                    showAllSources = true
                }
            }
        }
    }

    @ViewBuilder
    private func torrentRow(_ torrent: Torrent) -> some View {
        Button {
            action(torrent)
        } label: {
            #if os(iOS) || os(tvOS)
            Text(verbatim: "\(torrent.quality ?? "")\(sourceSuffix(torrent))\(localeSuffix(torrent)) (seeds: \(torrent.seeds) - peers: \(torrent.peers))")
            #elseif os(macOS)
            torrent.health.image
            Text(torrent.quality)
                .fontWeight(.bold)
            Text(verbatim: "\(sourceSuffix(torrent))\(localeSuffix(torrent)) (seeds: \(torrent.seeds) - peers: \(torrent.peers))")
                .foregroundColor(.appLightGray)
                .font(.system(size: 12, weight: .light))
            Spacer()
            #endif
        }
    }

    /// `" · BluRay"`, `" · WEB-DL"`, `" · CAM"`, etc. — surfaces the
    /// release source so users browsing the picker can spot a screener
    /// before they pick it.
    private func sourceSuffix(_ torrent: Torrent) -> String {
        switch torrent.releaseSource {
        case .bluray:   return " · BluRay"
        case .webdl:    return " · WEB-DL"
        case .webrip:   return " · WEBRip"
        case .hdtv:     return " · HDTV"
        case .dvdrip:   return " · DVDRip"
        case .screener: return " · CAM"
        case .unknown:  return ""
        }
    }

    /// `" · Russian, English"` etc. — the inferred audio tracks the picker
    /// derives from locale + title, so the user knows the actual language
    /// they're picking even on releases tagged under a different audience
    /// locale.
    private func localeSuffix(_ torrent: Torrent) -> String {
        let langs = torrent.audioLanguages
            .compactMap { Locale.current.localizedString(forLanguageCode: $0)?.capitalized }
            .sorted()
        guard !langs.isEmpty else { return "" }
        return " · \(langs.joined(separator: ", "))"
    }
}

struct SelectTorrentQualityAction_Previews: PreviewProvider {
    static var previews: some View {
        SelectTorrentQualityButton(media: Movie.dummy(), action: { torrent in
            print("selected: ", torrent)
        }, label: {
            Text("Play")
        })
            .preferredColorScheme(.dark)
    }
}
