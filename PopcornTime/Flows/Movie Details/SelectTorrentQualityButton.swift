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
            } else if let torrent = autoSelectTorrent {
                action(torrent)
            } else {
                showChooseQualityActionSheet = true
            }
        }, label: label)
        #if os(iOS) || os(tvOS)
        .confirmationDialog("Choose Quality", isPresented: $showChooseQualityActionSheet, titleVisibility: .visible, actions: {
            chooseTorrentsButtons
        })
        #elseif os(macOS)
        .popover(isPresented: $showChooseQualityActionSheet, content: {
            VStack {
                Text("Choose Quality")
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
                        if let torrent = autoSelectTorrent {
                            action(torrent)
                        } else {
                            showChooseQualityActionSheet = true
                        }
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

    /// Torrents that match the preferred audio language. Untagged torrents
    /// (e.g. YTS, which doesn't carry a locale field) are treated as English
    /// since YTS catalogues English-original releases.
    private var preferredLanguageTorrents: [Torrent] {
        guard let preferred = preferredLanguageFilter else { return media.torrents }
        return media.torrents.filter { ($0.locale ?? "en").lowercased() == preferred.lowercased() }
    }

    /// Pool to draw from when picking / showing torrents — respects the
    /// user's audio-language preference unless they've fallen back via the
    /// "no torrents in your language" alert.
    private var selectableTorrents: [Torrent] {
        if fallbackToAnyLanguage { return media.torrents }
        let filtered = preferredLanguageTorrents
        return filtered.isEmpty ? media.torrents : filtered
    }

    var autoSelectTorrent: Torrent? {
        let pool = selectableTorrents
        if let quality = Session.autoSelectQuality, !pool.isEmpty {
            let sorted = pool.sorted(by: <)
            return quality == "Highest" ? sorted.last : sorted.first
        }

        #if os(tvOS)
        if pool.count == 1 {
            return pool[0]
        }
        #endif

        return nil
    }

    @ViewBuilder
    var chooseTorrentsButtons: some View {
        ForEach(selectableTorrents.sorted(by: >)) { torrent in
            Button {
                action(torrent)
            } label: {
                #if os(iOS) || os(tvOS)
                Text(verbatim: "\(torrent.quality ?? "")\(localeSuffix(torrent)) (seeds: \(torrent.seeds) - peers: \(torrent.peers))")
                #elseif os(macOS)
                torrent.health.image
                Text(torrent.quality)
                    .fontWeight(.bold)
                Text(verbatim: "\(localeSuffix(torrent)) (seeds: \(torrent.seeds) - peers: \(torrent.peers))")
                    .foregroundColor(.appLightGray)
                    .font(.system(size: 12, weight: .light))
                Spacer()
                #endif
            }
        }
    }

    /// `" · Russian"` etc., or `""` when the torrent has no locale tag (YTS).
    private func localeSuffix(_ torrent: Torrent) -> String {
        guard let code = torrent.locale, !code.isEmpty,
              let display = Locale.current.localizedString(forLanguageCode: code)
        else { return "" }
        return " · \(display.capitalized)"
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
