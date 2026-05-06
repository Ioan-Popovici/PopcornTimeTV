//
//  SettingsView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 19.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    let theme = Theme()
    
    let subtitleSettings = SubtitleSettings.shared
    @StateObject var viewModel = SettingsViewModel()
    
    @State var showQualityAlert = false

    @State var showAudioLanguageAlert = false
    @State var selectedAudioLanguage = ""

    @State var showSubtitleLanguageAlert = false
    @State var showSubtitleFontSizeAlert = false
    @State var showSubtitleFontColorAlert = false
    @State var showSubtitleFontAlert = false
    @State var showSubtitleFontStyleAlert = false
    @State var showSubtitleEncondingAlert = false
    
    @State var showTraktAlert = false
    @State var showTraktView = false
    @Environment(\.openURL) var openURL
    
    @State var showClearCacheAlert = false
    
    @State var showOpenSubtitlesLogin = false
    @State var showOpenSubtitlesLogout = false
    @State var openSubtitlesUsername = ""
    @State var openSubtitlesPassword = ""
    
    @State var selectedSubtitleLanguage = ""
    
    
    /// Single dispatcher that picks the platform-tuned body. Each
    /// `<platform>Body` references the same shared row helpers (so a new
    /// setting only needs one `@ViewBuilder`), but each one is free to
    /// arrange them with the conventions that platform's Settings.app
    /// uses — section grouping, header/footer text density, list style,
    /// row chrome (icons on tvOS), and modal-vs-popover presentations.
    var body: some View {
        #if os(iOS)
        iOSBody
        #elseif os(tvOS)
        tvOSBody
        #elseif os(macOS)
        macOSBody
        #endif
    }

    // MARK: - iOS body

    /// iOS Settings convention: insetGrouped list, section headers in
    /// small caps, section footers in greyed footnote type, push-style
    /// detail navigation for selection lists. Most controls map 1:1 to
    /// SwiftUI's defaults — `Toggle` renders as a UISwitch, `Button`
    /// with `.destructive` role goes red, `TextField` is a plain row.
    #if os(iOS)
    var iOSBody: some View {
        HStack (spacing: theme.hStackSpacing) {
            Image("Icon")
                .padding(.leading, theme.iconLeading)
                .hideIfCompactSize()
            List {
                Section {
                    qualityAlertButton
                    bufferingStrategyButton
                    autoResumeToggle
                    showStreamingDetailsToggle
                    if viewModel.hasCellularNetwork {
                        streamOnCellularToggle
                    }
                } header: { Text("Playback") }
                  footer: { Text("Choose the auto-pick strategy, the buffering strategy, whether saved progress auto-resumes, what the loading screen shows, and where streaming is allowed.") }

                Section {
                    audioLanguageButton
                    subtitleLanguageButton
                } header: { Text("Language") }
                  footer: { Text("Audio language picks the torrent that contains the right track. Subtitle language preselects matching subtitles for download.") }

                Section {
                    subtitleFontSizeButton
                    subtitleFontColorButton
                    subtitleFontButton
                    subtitleFontStyleButton
                    subtitleEncondingButton
                } header: { Text("Subtitle Appearance") }

                Section {
                    trackButton
                    openSubtitlesButton
                } header: { Text("Accounts") }
                  footer: { Text("Sync watch history with Trakt and download additional subtitles from OpenSubtitles.com.") }

                popcornServerSection

                apiEndpointsSection

                Section {
                    removeCacheOnPlayerExitToggle
                    clearCacheButton
                } header: { Text("Storage") }
                  footer: { Text("Cached video data accumulates while you watch. Clearing it recovers disk space; the next play has to re-download.") }
            }
            .listStyle(.insetGrouped)
            .padding(.trailing, theme.iconLeading)
        }
        .navigationBarHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }
    #endif

    // MARK: - tvOS body

    /// tvOS Settings convention (Apple Music / TV / Podcasts): grouped
    /// list, every row has a leading SF Symbol icon (visual scanability
    /// matters far more on a 10-foot UI), no section footers (Apple
    /// drops them on tvOS — the explanation lives in the drill-down
    /// detail screen instead), boolean rows render as "Title · On/Off"
    /// rather than as switch widgets (Apple's own apps don't use UISwitch
    /// on tvOS — the Siri Remote has no precision drag, so a tappable
    /// row that flips its label is more direct), and selection lists
    /// present as modal sheets via `fullScreenContent`.
    #if os(tvOS)
    var tvOSBody: some View {
        HStack(spacing: theme.hStackSpacing) {
            Image("Icon")
                .padding(.leading, theme.iconLeading)
                .hideIfCompactSize()
            List {
                Section { Text("Playback") }
                Section {
                    tvOSChoiceRow(icon: "wand.and.stars",
                                  title: "Auto Select Quality",
                                  value: Session.autoSelectQuality.localized) {
                        showQualityAlert = true
                    }
                    tvOSChoiceRow(icon: "speedometer",
                                  title: "Buffering Strategy",
                                  value: bufferingStrategy.localized) {
                        showBufferingStrategyAlert = true
                    }
                    tvOSToggleRow(icon: "play.circle",
                                  title: "Auto-Resume Playback",
                                  isOn: $autoResume) { Session.autoResume = $0 }
                    tvOSToggleRow(icon: "info.circle",
                                  title: "Show Streaming Details",
                                  isOn: $showStreamingDetails) { Session.showStreamingDetails = $0 }
                    if viewModel.hasCellularNetwork {
                        tvOSToggleRow(icon: "antenna.radiowaves.left.and.right",
                                      title: "Stream on Cellular",
                                      isOn: $streamOnCellular) { Session.streamOnCellular = $0 }
                    }
                }

                Section { Text("Language") }
                Section {
                    tvOSChoiceRow(icon: "speaker.wave.2.fill",
                                  title: "Audio Language",
                                  value: audioLanguageDisplay) {
                        showAudioLanguageAlert = true
                    }
                    tvOSChoiceRow(icon: "captions.bubble.fill",
                                  title: "Subtitle Language",
                                  value: subtitleSettings.language ?? "None".localized) {
                        showSubtitleLanguageAlert = true
                    }
                }

                Section { Text("Subtitle Appearance") }
                Section {
                    tvOSChoiceRow(icon: "textformat.size",
                                  title: "Size",
                                  value: subtitleSettings.size.localizedString) {
                        showSubtitleFontSizeAlert = true
                    }
                    tvOSChoiceRow(icon: "paintpalette.fill",
                                  title: "Color",
                                  value: SubtitleColor.allCases.first(where: { $0 == subtitleSettings.color })?.localizedString ?? "") {
                        showSubtitleFontColorAlert = true
                    }
                    tvOSChoiceRow(icon: "textformat",
                                  title: "Font",
                                  value: subtitleSettings.fontFamilyName) {
                        showSubtitleFontAlert = true
                    }
                    tvOSChoiceRow(icon: "italic",
                                  title: "Style",
                                  value: subtitleSettings.style.localizedString) {
                        showSubtitleFontStyleAlert = true
                    }
                    tvOSChoiceRow(icon: "character.book.closed.fill",
                                  title: "Encoding",
                                  value: subtitleSettings.encoding) {
                        showSubtitleEncondingAlert = true
                    }
                }

                Section { Text("Accounts") }
                Section {
                    trackButton
                    openSubtitlesButton
                }

                Section { Text("Storage") }
                Section {
                    tvOSToggleRow(icon: "trash.slash",
                                  title: "Clear Cache Upon Exit",
                                  isOn: $clearCacheOnExit) { Session.removeCacheOnPlayerExit = $0 }
                    clearCacheButton
                }
            }
            .listStyle(GroupedListStyle())
            .padding(.trailing, theme.iconLeading)
        }
        // Modal presentations live at the body level so they don't get
        // reattached every time a row redraws. tvOS uses
        // `fullScreenContent` for selection lists per Apple HIG.
        .fullScreenContent(isPresented: $showQualityAlert, title: "Auto Select Quality") {
            QualityPickerView()
        }
        .confirmationDialog("Buffering Strategy", isPresented: $showBufferingStrategyAlert, titleVisibility: .visible, actions: {
            ForEach(["Fast", "Balanced", "Smooth"], id: \.self) { strategy in
                Button(strategy.localized) {
                    bufferingStrategy = strategy
                    Session.bufferingStrategy = strategy
                }
            }
            Button("Cancel", role: .cancel) { }
        }, message: { Text(bufferingDescription(for: bufferingStrategy)) })
        .actionSheet(isPresented: $showAudioLanguageAlert) { audioLanguageAlert }
        .actionSheet(isPresented: $showSubtitleLanguageAlert) { subtitleLanguageAlert }
        .actionSheet(isPresented: $showSubtitleFontSizeAlert) { subtitleFontSizeAlert }
        .actionSheet(isPresented: $showSubtitleFontColorAlert) { subtitleFontColorAlert }
        .actionSheet(isPresented: $showSubtitleFontAlert) { subtitleFontAlert }
        .actionSheet(isPresented: $showSubtitleFontStyleAlert) { subtitleFontStyleAlert }
        .actionSheet(isPresented: $showSubtitleEncondingAlert) { subtitleEncondingAlert }
    }
    #endif

    // MARK: - macOS body

    /// macOS System Settings convention (Ventura+): `Form` with
    /// `.formStyle(.grouped)` for rounded-card sections, native
    /// `Picker(.menu)` dropdowns inline in rows (not popovers — Apple
    /// reserves popovers for richer pickers; basic enumerations get a
    /// dropdown directly in the row), `LabeledContent` to align labels
    /// with their controls, system default fonts (Form's body text is
    /// 13pt — `theme.fontSize` of 20pt blew up rows visibly), and
    /// `Button(role: .destructive)` rendered in red.
    #if os(macOS)
    /// Local mirror of the persisted quality choice for the macOS
    /// `Picker`. Updated on every render so external changes (e.g. the
    /// long-press shortcut writing a different value) re-sync.
    @State private var macOSQualitySelection: String = Session.autoSelectQuality

    /// Toggled after each storage-path change to force the Storage
    /// Section to rebuild. The displayed paths come from static
    /// `Session.streamingCachePath` / `Session.savedDownloadsPath`,
    /// which aren't observable — `.id()` on the Section ties its
    /// identity to this state so a flip triggers a re-render.
    @State private var storageRefreshTrigger: Bool = false

    /// One-line description for the currently-selected quality mode —
    /// rendered as the section footer so the explanation tracks the
    /// dropdown selection. Same copy as `QualityPickerView` so the two
    /// surfaces stay consistent.
    private func qualityDescription(for value: String) -> String {
        switch value {
        case "Optimal":
            return "Adaptive — picks the best source by composite quality (release tier > resolution > seeds). Recommended.".localized
        case "Highest":
            return "Always picks the highest resolution available. May take longer to start on 4K sources or weak swarms.".localized
        case "Low":
            return "Lowest resolution for the fastest start and lowest bandwidth. Useful on slow or metered connections.".localized
        case "Selectable":
            return "Shows the source picker every time you tap Play, so you can pick the exact release.".localized
        default:
            return ""
        }
    }

    /// Storage-path row used twice in the macOS Storage section, once
    /// for the streaming cache and once for saved downloads. Path is
    /// shown in `~`-abbreviated, monospaced, middle-truncated form so
    /// long Containers paths stay readable. Reset only renders when an
    /// override is active — for the default path there's nothing to
    /// reset to.
    @ViewBuilder
    private func storagePathRow(
        label: LocalizedStringKey,
        path: String,
        isOverridden: Bool,
        onChoose: @escaping (URL) -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Button("Choose…") { chooseFolder(handler: onChoose) }
                if isOverridden {
                    Button("Reset", action: onReset)
                }
            }
        } label: {
            Text(label)
        }
    }

    /// Open an NSOpenPanel rooted at the user's home, restricted to
    /// directories. macOS sandbox grants read-write access to whatever
    /// the user selects via `com.apple.security.files.user-selected.
    /// read-write`; Session captures a security-scoped bookmark from
    /// the returned URL so the access survives across launches.
    private func chooseFolder(handler: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder PopcornTime can use for this storage location."
        if panel.runModal() == .OK, let url = panel.url {
            handler(url)
        }
    }

    var macOSBody: some View {
        Form {
            // Per-control helper rows live directly under each Picker so
            // the description tracks the dropdown it explains, mirroring
            // System Settings → Display & Brightness (helper text under
            // the relevant control, not stacked at the section footer).
            Section {
                Picker("Auto Select Quality", selection: $macOSQualitySelection) {
                    Text("Optimal").tag("Optimal")
                    Text("Highest").tag("Highest")
                    Text("Low").tag("Low")
                    Text("Selectable").tag("Selectable")
                }
                .pickerStyle(.menu)
                .onChange(of: macOSQualitySelection) { _, v in
                    Session.autoSelectQuality = v
                }
                Text(qualityDescription(for: macOSQualitySelection))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Buffering Strategy", selection: $bufferingStrategy) {
                    Text("Fast").tag("Fast")
                    Text("Balanced").tag("Balanced")
                    Text("Smooth").tag("Smooth")
                }
                .pickerStyle(.menu)
                .onChange(of: bufferingStrategy) { _, v in
                    Session.bufferingStrategy = v
                }
                Text(bufferingDescription(for: bufferingStrategy))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-Resume Playback", isOn: $autoResume)
                    .onChange(of: autoResume) { _, v in Session.autoResume = v }
                Text("On: tap Play to jump straight to the saved position. Off: tap Play to start from the beginning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show Streaming Details", isOn: $showStreamingDetails)
                    .onChange(of: showStreamingDetails) { _, v in Session.showStreamingDetails = v }

                if viewModel.hasCellularNetwork {
                    Toggle("Stream on Cellular", isOn: $streamOnCellular)
                        .onChange(of: streamOnCellular) { _, v in Session.streamOnCellular = v }
                }
            } header: {
                Text("Playback")
            }

            Section {
                Picker("Audio Language", selection: $selectedAudioLanguage) {
                    ForEach(["Any"] + Locale.commonLanguages, id: \.self) { language in
                        Text(language.localized).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedAudioLanguage) { _, newValue in
                    if newValue == "Any" {
                        Session.preferredAudioLanguage = ""
                    } else if let code = Self.languageCode(for: newValue) {
                        Session.preferredAudioLanguage = code
                    }
                }

                Picker("Subtitle Language", selection: $selectedSubtitleLanguage) {
                    ForEach(["None"] + Locale.commonLanguages, id: \.self) { language in
                        Text(language.localized).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedSubtitleLanguage) { _, newValue in
                    subtitleSettings.language = newValue == "None" ? nil : newValue
                    subtitleSettings.save()
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Audio language picks torrents whose audio track matches. Subtitle language pre-selects matching subtitles when downloading.")
            }

            Section {
                LabeledContent("Trakt") {
                    Button(viewModel.isTraktLoggedIn ? "Sign Out" : "Sign In") {
                        if viewModel.isTraktLoggedIn { showTraktAlert = true }
                        else { showTraktView = true }
                    }
                }
                LabeledContent("OpenSubtitles.com") {
                    HStack(spacing: 6) {
                        if viewModel.isOpenSubtitlesLoading {
                            ProgressView().controlSize(.small)
                        }
                        Button(viewModel.isOpenSubtitlesLoggedIn ? "Sign Out" : "Sign In") {
                            if viewModel.isOpenSubtitlesLoggedIn { showOpenSubtitlesLogout = true }
                            else { showOpenSubtitlesLogin = true }
                        }
                    }
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Sync watch history with Trakt; download additional subtitles via OpenSubtitles.com.")
            }

            popcornServerSection

            apiEndpointsSection

            Section {
                storagePathRow(
                    label: "Streaming Cache",
                    path: Session.streamingCachePath,
                    isOverridden: Session.hasStreamingCacheOverride,
                    onChoose: { url in
                        Session.setStreamingCachePath(url)
                        storageRefreshTrigger.toggle()
                    },
                    onReset: {
                        Session.setStreamingCachePath(nil)
                        storageRefreshTrigger.toggle()
                    }
                )
                storagePathRow(
                    label: "Downloads",
                    path: Session.savedDownloadsPath,
                    isOverridden: Session.hasSavedDownloadsOverride,
                    onChoose: { url in
                        Session.setSavedDownloadsPath(url)
                        storageRefreshTrigger.toggle()
                    },
                    onReset: {
                        Session.setSavedDownloadsPath(nil)
                        storageRefreshTrigger.toggle()
                    }
                )
                Toggle("Clear cache on quit", isOn: $clearCacheOnExit)
                    .onChange(of: clearCacheOnExit) { _, v in Session.removeCacheOnPlayerExit = v }
                Button(role: .destructive) {
                    // Clear synchronously, capture the result message,
                    // *then* trigger the alert so its body sees the
                    // updated `viewModel.clearCache.message`.
                    viewModel.clearCache.emptyCache()
                    showClearCacheAlert = true
                } label: {
                    Text("Clear All Cache Now")
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Cache holds in-flight streaming pieces (wiped on Clear All Cache). Downloads holds completed saves. Changing a folder applies to new playback / downloads — existing files stay where they are.")
            }
            // `storageRefreshTrigger` makes SwiftUI recompute the Form
            // body when an override changes — without it the path Texts
            // (which read static `Session` values, not `@State`) would
            // continue showing the old path until the view rebuilt.
            .id(storageRefreshTrigger)
        }
        .formStyle(.grouped)
        // Result confirmation for "Clear All Cache" — attached at the
        // Form level rather than to the Button itself. macOS Form
        // intercepts some modifier attachments on nested Buttons, so
        // the dialog would silently fail to present. Using
        // `confirmationDialog` rather than `alert` to match the rest
        // of the SettingsView's modal pattern (Trakt sign-out etc).
        .confirmationDialog(
            "Clear Cache",
            isPresented: $showClearCacheAlert,
            titleVisibility: .visible,
            actions: { Button("OK") {} },
            message: { Text(viewModel.clearCache.message) }
        )
        // Trakt sign-out + sign-in attached at body level so they aren't
        // re-bound on every row redraw.
        .fullScreenContent(isPresented: $showTraktView, title: "Trakt") {
            TraktView(viewModel: TraktViewModel(onSuccess: {
                self.viewModel.traktDidLoggedIn()
                self.showTraktView = false
            }))
        }
        .confirmationDialog("Sign Out", isPresented: $showTraktAlert, actions: {
            Button("Sign Out") { viewModel.traktLogout() }
            Button("Cancel", role: .cancel, action: {})
        }, message: { Text("Are you sure you want to Sign Out?") })
        .alert("OpenSubtitles.com", isPresented: $showOpenSubtitlesLogin) {
            TextField("Username", text: $openSubtitlesUsername)
                .textContentType(.username).textCase(.lowercase)
            SecureField("Password", text: $openSubtitlesPassword)
                .textContentType(.password)
            Button("Cancel") {
                showOpenSubtitlesLogin = false
                openSubtitlesUsername = ""; openSubtitlesPassword = ""
                viewModel.openSubtitlesLoginError = nil
            }
            Button("Login") {
                viewModel.openSubtitlesLogin(username: openSubtitlesUsername, password: openSubtitlesPassword)
            }
            .disabled(openSubtitlesUsername.isEmpty || openSubtitlesPassword.isEmpty || viewModel.isOpenSubtitlesLoading)
        } message: {
            if let error = viewModel.openSubtitlesLoginError, !error.isEmpty {
                Text("Error: \(error)")
            } else {
                Text("Sign in to download subtitles.")
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showOpenSubtitlesLogout, actions: {
            Button("Sign Out") { viewModel.openSubtitlesLogout() }
            Button("Cancel", role: .cancel) { }
        }, message: { Text("Are you sure you want to sign out of OpenSubtitles?") })
        .onAppear {
            // Mirror the persisted language codes into the macOS Picker
            // bindings on first appear; the picker stores the localised
            // *display name*, but Session stores the ISO code.
            let audioCode = Session.preferredAudioLanguage
            if audioCode.isEmpty {
                selectedAudioLanguage = "Any"
            } else if let name = Locale.current.localizedString(forLanguageCode: audioCode) {
                selectedAudioLanguage = name.capitalized
            } else {
                selectedAudioLanguage = "Any"
            }
            selectedSubtitleLanguage = subtitleSettings.language ?? "None"
        }
        .onChange(of: viewModel.isOpenSubtitlesLoggedIn) { _, loggedIn in
            if loggedIn {
                showOpenSubtitlesLogin = false
                openSubtitlesUsername = ""; openSubtitlesPassword = ""
            }
        }
    }
    #endif

    // MARK: - tvOS row helpers

    #if os(tvOS)
    /// "Title · value · chevron" row prefixed with an SF Symbol —
    /// used for any tappable row that opens a detail screen. Mirrors
    /// the visual pattern of every row in Apple Music's tvOS Settings.
    @ViewBuilder
    private func tvOSChoiceRow(
        icon: String,
        title: LocalizedStringKey,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 36)
                Text(title)
                Spacer()
                Text(value)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: theme.fontSize, weight: .medium))
        }
    }

    /// Boolean row in tvOS style — title on the left, "On" / "Off"
    /// text on the right. Tapping anywhere on the row toggles the
    /// value. Apple does not use UISwitch on tvOS because the Siri
    /// Remote has no drag-to-toggle gesture.
    @ViewBuilder
    private func tvOSToggleRow(
        icon: String,
        title: LocalizedStringKey,
        isOn: Binding<Bool>,
        write: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            write(isOn.wrappedValue)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 36)
                Text(title)
                Spacer()
                Text(isOn.wrappedValue ? "On".localized : "Off".localized)
                    .foregroundColor(.secondary)
            }
            .font(.system(size: theme.fontSize, weight: .medium))
        }
    }
    #endif

    
    /// Mirror Session-backed booleans into local @State so SwiftUI
    /// rebuilds the Toggle row when the user flips it. The didSet
    /// hooks write back to the Session UserDefaults wrapper.
    @State private var clearCacheOnExit: Bool = Session.removeCacheOnPlayerExit
    @State private var streamOnCellular: Bool = Session.streamOnCellular
    @State private var showStreamingDetails: Bool = Session.showStreamingDetails
    @State private var bufferingStrategy: String = Session.bufferingStrategy
    @State private var showBufferingStrategyAlert = false
    @State private var autoResume: Bool = Session.autoResume

    /// Auto-resume toggle — when on (default), the player jumps straight
    /// to the saved position; when off, playback starts from the
    /// beginning. There's no in-player prompt either way; this toggle is
    /// the single control. The PlayButton's "Resume" label flips
    /// whenever progress exists, regardless of this toggle, since the
    /// label answers "is there saved state?".
    @ViewBuilder
    var autoResumeToggle: some View {
        Toggle("Auto-Resume Playback", isOn: $autoResume)
            .font(.system(size: theme.fontSize, weight: .medium))
            .onChange(of: autoResume) { _, newValue in
                Session.autoResume = newValue
            }
    }

    @ViewBuilder
    var removeCacheOnPlayerExitToggle: some View {
        Toggle("Clear Cache Upon Exit", isOn: $clearCacheOnExit)
            .font(.system(size: theme.fontSize, weight: .medium))
            .onChange(of: clearCacheOnExit) { _, newValue in
                Session.removeCacheOnPlayerExit = newValue
            }
    }

    @ViewBuilder
    var streamOnCellularToggle: some View {
        Toggle("Stream on cellular network", isOn: $streamOnCellular)
            .font(.system(size: theme.fontSize, weight: .medium))
            .onChange(of: streamOnCellular) { _, newValue in
                Session.streamOnCellular = newValue
            }
    }

    /// Toggle that flips `Session.showStreamingDetails` — when off,
    /// the preload screen renders just a centered spinner instead of
    /// the linear bar + stats panel + status text. Lives in the
    /// Playback section of every platform body.
    @ViewBuilder
    var showStreamingDetailsToggle: some View {
        Toggle("Show Streaming Details", isOn: $showStreamingDetails)
            .font(.system(size: theme.fontSize, weight: .medium))
            .onChange(of: showStreamingDetails) { _, newValue in
                Session.showStreamingDetails = newValue
            }
    }

    /// iOS / tvOS row that opens the Buffering Strategy
    /// confirmation dialog. macOS bypasses this and renders an
    /// inline `Picker(.menu)` directly.
    @ViewBuilder
    var bufferingStrategyButton: some View {
        button(text: "Buffering Strategy", value: bufferingStrategy.localized) {
            showBufferingStrategyAlert = true
        }
        #if os(iOS) || os(tvOS)
        .confirmationDialog("Buffering Strategy", isPresented: $showBufferingStrategyAlert, titleVisibility: .visible, actions: {
            ForEach(["Fast", "Balanced", "Smooth"], id: \.self) { strategy in
                Button(strategy.localized) {
                    bufferingStrategy = strategy
                    Session.bufferingStrategy = strategy
                }
            }
            Button("Cancel", role: .cancel) { }
        }, message: { Text(bufferingDescription(for: bufferingStrategy)) })
        #endif
    }

    /// One-liner explaining what each buffering strategy means.
    /// Reused as the macOS Picker's dynamic footer (changes with
    /// the dropdown selection) and the iOS/tvOS confirmation
    /// dialog's `message`.
    func bufferingDescription(for value: String) -> String {
        switch value {
        case "Fast":
            return "Wait for 3 head pieces (~3–6 MB) before starting. Snappiest first frame; tightest tolerance for weak swarms.".localized
        case "Balanced":
            return "Wait for 4 head pieces (~4–8 MB) before starting. Good default — works on most swarms.".localized
        case "Smooth":
            return "Wait for 8 head pieces (~8–16 MB) before starting. More upfront wait, more cushion against immediate stalls on slow connections.".localized
        default:
            return ""
        }
    }
    
    /// Apple HIG pattern for "single selection from options with rich
    /// per-option context": tapping the row presents a detail screen
    /// showing every option with its title + description + checkmark.
    /// This mirrors iOS Settings → Display → Auto-Lock and macOS System
    /// Settings → Lock Screen, where each option is annotated with what
    /// it does so the user can decide before committing.
    @ViewBuilder
    var qualityAlertButton: some View {
        // `currentQuality` is read fresh on every render so the
        /// row re-mirrors the new selection after the picker dismisses.
        let current = Session.autoSelectQuality
        button(text: "Auto Select Quality", value: current.localized) {
            showQualityAlert = true
        }
        #if os(tvOS) || os(iOS)
        .fullScreenContent(isPresented: $showQualityAlert, title: "Auto Select Quality") {
            QualityPickerView()
        }
        #else
        .popover(isPresented: $showQualityAlert) {
            QualityPickerView()
                .frame(width: 460, height: 380)
        }
        #endif
    }

    /// Drives the value shown in the "Audio Language" row. Empty string
    /// in `Session.preferredAudioLanguage` means "no preference / any".
    private var audioLanguageDisplay: String {
        let raw = Session.preferredAudioLanguage
        if raw.isEmpty { return "Any".localized }
        return Locale.current.localizedString(forLanguageCode: raw)?.capitalized ?? raw
    }

    @ViewBuilder
    var audioLanguageButton: some View {
        #if os(tvOS) || os(iOS)
        button(text: "Audio Language", value: audioLanguageDisplay) {
            showAudioLanguageAlert = true
        }
        .actionSheet(isPresented: $showAudioLanguageAlert) {
            audioLanguageAlert
        }
        #else
        HStack {
            Text("Audio Language".localized)
            Spacer()
            Picker("", selection: $selectedAudioLanguage) {
                ForEach(["Any"] + Locale.commonLanguages, id: \.self) { language in
                    Text(language.localized).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
            .onChange(of: selectedAudioLanguage) { _, newValue in
                if newValue == "Any" {
                    Session.preferredAudioLanguage = ""
                } else if let code = Self.languageCode(for: newValue) {
                    Session.preferredAudioLanguage = code
                }
            }
        }
        .font(.system(size: theme.fontSize, weight: .medium))
        .onAppear {
            // Translate the stored language code back into the human-readable
            // name the picker uses (e.g. "en" → "English").
            let code = Session.preferredAudioLanguage
            if code.isEmpty {
                selectedAudioLanguage = "Any"
            } else if let name = Locale.current.localizedString(forLanguageCode: code) {
                selectedAudioLanguage = name.capitalized
            } else {
                selectedAudioLanguage = "Any"
            }
        }
        #endif
    }

    #if os(tvOS) || os(iOS)
    var audioLanguageAlert: ActionSheet {
        let values = ["Any"] + Locale.commonLanguages
        let actions = values.map { language -> Alert.Button in
            Alert.Button.default(Text(language.localized)) {
                if language == "Any" {
                    Session.preferredAudioLanguage = ""
                } else if let code = Self.languageCode(for: language) {
                    Session.preferredAudioLanguage = code
                }
            }
        }
        return ActionSheet(
            title: Text("Audio Language"),
            message: Text("Pick the audio language the torrent picker should prefer. Movies without a torrent in this language will prompt before falling back."),
            buttons: [.cancel()] + actions
        )
    }
    #endif

    /// Map a localized language name (`"English"`) back to the ISO 639-1
    /// code (`"en"`) we store in `Session.preferredAudioLanguage`. Iterates
    /// the same curated set the picker shows.
    static func languageCode(for displayName: String) -> String? {
        for code in Locale.commonISOLanguageCodes {
            if let name = Locale.current.localizedString(forLanguageCode: code),
               name.caseInsensitiveCompare(displayName) == .orderedSame {
                return code
            }
        }
        return nil
    }

    @ViewBuilder
    var subtitleLanguageButton: some View {
        #if os(tvOS) || os(iOS)
        button(text: "Language", value: subtitleSettings.language ?? "None".localized) {
            showSubtitleLanguageAlert = true
        }
        .actionSheet(isPresented: $showSubtitleLanguageAlert) {
            subtitleLanguageAlert
        }
        #else
        HStack {
            Text("Language".localized)
            Spacer()
            Picker("", selection: $selectedSubtitleLanguage) {
                ForEach(["None"] + Locale.commonLanguages, id: \.self) { language in
                    Text(language.localized).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)
            .onChange(of: selectedSubtitleLanguage) { _, newValue in
                subtitleSettings.language = newValue == "None" ? nil : newValue
                subtitleSettings.save()
            }
        }
        .font(.system(size: theme.fontSize, weight: .medium))
        .onAppear {
            selectedSubtitleLanguage = subtitleSettings.language ?? "None"
        }
        #endif
    }
    
    #if os(tvOS) || os(iOS)
    var subtitleLanguageAlert: ActionSheet {
        let values = ["None"] + Locale.commonLanguages
        let actions = values.map ({ language -> Alert.Button in
            return Alert.Button.default(Text(language.localized)) {
                subtitleSettings.language = language == "None".localized ? nil : language
                subtitleSettings.save()
            }
        })
        
        return ActionSheet(title: Text("Subtitle Language"),
                    message: Text("Choose a default language for the player subtitles."),
                    buttons:[
                        .cancel(),
                    ] + actions
        )
    }
    
    @ViewBuilder
    var subtitleFontSizeButton: some View {
        button(text: "Size", value: subtitleSettings.size.localizedString) {
            showSubtitleFontSizeAlert = true
        }
        .actionSheet(isPresented: $showSubtitleFontSizeAlert) {
            subtitleFontSizeAlert
        }
    }
    
    var subtitleFontSizeAlert: ActionSheet {
        let values = SubtitleSettings.Size.allCases
        let actions = values.map ({ size -> Alert.Button in
            return Alert.Button.default(Text(size.localizedString)) {
                subtitleSettings.size = size
                subtitleSettings.save()
            }
        })
        
        return ActionSheet(title: Text("Subtitle Font Size"),
                    message: Text("Choose a font size for the player subtitles."),
                    buttons:[
                        .cancel(),
                    ] + actions
        )
    }
    
    @ViewBuilder
    var subtitleFontColorButton: some View {
        let colorValue = SubtitleColor.allCases.first(where: {$0 == subtitleSettings.color})?.localizedString ?? ""
        button(text: "Color", value: colorValue) {
            showSubtitleFontColorAlert = true
        }
        .actionSheet(isPresented: $showSubtitleFontColorAlert) {
            subtitleFontColorAlert
        }
    }
    
    var subtitleFontColorAlert: ActionSheet {
        let values = SubtitleColor.allCases
        let actions = values.map ({ color -> Alert.Button in
            return Alert.Button.default(Text(color.localizedString)) {
                subtitleSettings.color = color
                subtitleSettings.save()
            }
        })
        
        return ActionSheet(title: Text("Subtitle Color"),
                    message: Text("Choose text color for the player subtitles."),
                    buttons:[
                        .cancel(),
                    ] + actions
        )
    }
    
    
    @ViewBuilder
    var subtitleFontButton: some View {
        button(text: "Font", value: subtitleSettings.fontFamilyName) {
            showSubtitleFontAlert = true
        }
        .actionSheet(isPresented: $showSubtitleFontAlert) {
            subtitleFontAlert
        }
    }
    
    var subtitleFontAlert: ActionSheet {
        let values = Font.familyNames
        let actions = values.map ({ fontFamily -> Alert.Button in
            return Alert.Button.default(Text(fontFamily)) {
                guard let fontName = Font.fontName(familyName: fontFamily) else {
                    return
                }
                subtitleSettings.fontName = fontName
                subtitleSettings.fontFamilyName = fontFamily
                subtitleSettings.save()
            }
        })
        
        return ActionSheet(title: Text("Subtitle Font"),
                    message: Text("Choose a default font for the player subtitles."),
                    buttons:[
                        .cancel(),
                    ] + actions
        )
    }
    
    @ViewBuilder
    var subtitleFontStyleButton: some View {
        button(text: "Style", value: subtitleSettings.style.localizedString) {
            showSubtitleFontStyleAlert = true
        }
        .actionSheet(isPresented: $showSubtitleFontStyleAlert) {
            subtitleFontStyleAlert
        }
    }
    
    var subtitleFontStyleAlert: ActionSheet {
        let values = FontStyle.arrayValue
        let actions = values.map ({ style -> Alert.Button in
            return Alert.Button.default(Text(style.localizedString)) {
                subtitleSettings.style = style
                subtitleSettings.save()
            }
        })
        
        return ActionSheet(title: Text("Subtitle Font Style"),
                    message: Text("Choose a default font style for the player subtitles."),
                    buttons:[
                        .cancel(),
                    ] + actions
        )
    }
    
    @ViewBuilder
    var subtitleEncondingButton: some View {
        button(text: "Encoding", value: subtitleSettings.encoding) {
            showSubtitleEncondingAlert = true
        }
        .actionSheet(isPresented: $showSubtitleEncondingAlert) {
            subtitleEncondingAlert
        }
    }
    
    var subtitleEncondingAlert: ActionSheet {
        let subtitleSettings = SubtitleSettings.shared
        let values = SubtitleSettings.encodings.sorted(by: { $0.0 < $1.0 })
        
        let actions = values.map ({ (title, value) -> Alert.Button in
            return Alert.Button.default(Text(title.localized)) {
                subtitleSettings.encoding = value
                subtitleSettings.save()
            }
        })
        
        return ActionSheet(title: Text("Subtitle Encoding"),
                    message: Text("Choose encoding for the player subtitles."),
                    buttons:[
                        .cancel(),
                    ] + actions
        )
    }
#endif
    
    @ViewBuilder
    var clearCacheButton: some View {
        // Apple HIG: a destructive action gets `role: .destructive`
        // which renders red on iOS / macOS / tvOS automatically — no
        // need to manually apply `.foregroundColor(.red)`.
        Button(role: .destructive) {
            viewModel.clearCache.emptyCache()
            showClearCacheAlert = true
        } label: {
            HStack {
                Text("Clear All Cache")
                Spacer()
            }
            .font(.system(size: theme.fontSize, weight: .medium))
        }
        #if os(macOS)
        .buttonStyle(.borderless)
        #endif
        .confirmationDialog(viewModel.clearCache.message, isPresented: $showClearCacheAlert, titleVisibility: .visible, actions: {
            Button("OK") {}
        })
    }


    @ViewBuilder
    var trackButton: some View {
        let tracktValue = viewModel.isTraktLoggedIn ? "Sign Out".localized : "Sign In".localized
        button(text: "Trakt", value: tracktValue) {
            if viewModel.isTraktLoggedIn {
                showTraktAlert = true
            } else  {
                #if os(tvOS) || os(macOS)
                showTraktView = true
                #else
                openURL(viewModel.traktAuthorizationUrl)
                #endif
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showTraktAlert, actions: {
            Button("Sign Out") {
                viewModel.traktLogout()
            }
            Button("Cancel", role: .cancel, action: {})
        }, message: { Text("Are you sure you want to Sign Out?") })
        #if os(tvOS) || os(macOS)
        .fullScreenContent(isPresented: $showTraktView, title: "Trakt") {
            TraktView(viewModel: TraktViewModel(onSuccess: {
                self.viewModel.traktDidLoggedIn()
                self.showTraktView = false
            }))
        }
        #else
        .onOpenURL { url in
            viewModel.validate(traktUrl: url)
        }
        #endif
    }
    
    @ViewBuilder
    var openSubtitlesButton: some View {
        let buttonValue = viewModel.isOpenSubtitlesLoggedIn ? "Sign Out".localized : "Sign In".localized
        let isLoadingView: AnyView = {
            if !viewModel.isOpenSubtitlesLoading {
                return AnyView(EmptyView())
            } else {
                return AnyView(ProgressView())
            }
        }()
        
        button(text: "OpenSubtitles.com", value: buttonValue, customView:isLoadingView) {
            if viewModel.isOpenSubtitlesLoggedIn {
                showOpenSubtitlesLogout = true
            } else {
                showOpenSubtitlesLogin = true
            }
        }
        .alert("OpenSubtitles.com", isPresented: $showOpenSubtitlesLogin) {
            TextField("Username", text: $openSubtitlesUsername)
                .textContentType(.username)
                .textCase(.lowercase)
            SecureField("Password", text: $openSubtitlesPassword)
                .textContentType(.password)
            
            Button("Cancel") {
                showOpenSubtitlesLogin = false
                openSubtitlesUsername = ""
                openSubtitlesPassword = ""
                viewModel.openSubtitlesLoginError = nil
            }
            
            Button("Login") {
                viewModel.openSubtitlesLogin(username: openSubtitlesUsername, password: openSubtitlesPassword)
            }
            .disabled(openSubtitlesUsername.isEmpty || openSubtitlesPassword.isEmpty || viewModel.isOpenSubtitlesLoading)
        } message: {
            if viewModel.isOpenSubtitlesLoading {
                ProgressView()
            } else if let error = viewModel.openSubtitlesLoginError {
                Text("Error: \(error)")
            } else {
                Text("Sign in to your account to download subtitles")
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showOpenSubtitlesLogout, actions: {
            Button("Sign Out") {
                viewModel.openSubtitlesLogout()
            }
            Button("Cancel", role: .cancel) { }
        }, message: {
            Text("Are you sure you want to sign out of OpenSubtitles?")
        })
        .onChange(of: viewModel.isOpenSubtitlesLoggedIn) { _, loggedIn in
            if loggedIn {
                showOpenSubtitlesLogin = false
                openSubtitlesUsername = ""
                openSubtitlesPassword = ""
            }
        }
        .onChange(of: viewModel.openSubtitlesLoginError) { _, loginError in
            if loginError?.isEmpty == false {
                showOpenSubtitlesLogin = true
            }
        }
    }
    
    func button(text: LocalizedStringKey, value: String, customView: some View = EmptyView(), action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
        }, label: {
            HStack {
                Text(text)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
                if !(customView is EmptyView) {
                    customView
                }
            }
            .font(.system(size: theme.fontSize, weight: .medium))
        })
        #if os(macOS)
        .buttonStyle(.borderless)
        #endif
    }
    
    func sectionHeader(_ text: String) -> some View {
        return Text(text.localized.uppercased())
    }

    // MARK: - Popcorn server list

    /// List-shape UI for the Popcorn API server fallback list. Each
    /// row is a single URL; the user can swipe-to-delete on iOS or
    /// tap the inline `−` on macOS, add a new URL via the "Add Server"
    /// row at the bottom, and reset the whole list to the bundled
    /// `Popcorn.fallbackMirrors` defaults. Skipped on tvOS — same
    /// reasoning as `apiEndpointsSection` (in-list TextField focus
    /// is awkward there).
    @ViewBuilder
    var popcornServerSection: some View {
        #if os(macOS) || os(iOS)
        Section {
            ForEach(viewModel.popcornUrls, id: \.self) { url in
                #if os(macOS)
                HStack {
                    Text(url)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        viewModel.removePopcornUrl(url)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove server")
                }
                #else
                Text(url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                #endif
            }
            #if os(iOS)
            .onDelete { offsets in viewModel.removePopcornUrls(at: offsets) }
            #endif

            HStack {
                TextField(
                    "https://example.com",
                    text: $viewModel.newPopcornUrl
                )
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #else
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit { viewModel.addPopcornUrl() }
                let canAdd = !viewModel.newPopcornUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    viewModel.addPopcornUrl()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(canAdd ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }

            Button {
                viewModel.restorePopcornUrlDefaults()
            } label: {
                Text("Restore Defaults")
            }
        } header: {
            Text("Popcorn API Servers")
        } footer: {
            Text("The app tries each server in order until one responds. Add custom servers for testing or restore the bundled defaults.")
        }
        #else
        EmptyView()
        #endif
    }

    // MARK: - API Endpoints (testing)

    /// Editable URLs for every public API the app fetches from
    /// (Trakt, TMDB, Fanart, OpenSubtitles, OMDb, YTS, DHT). Active
    /// values are read at first access of `<Service>.base`, so
    /// changes apply on next app launch — the footer makes that
    /// explicit. Skipped on tvOS where in-place text editing inside
    /// a settings list is awkward (focus, on-screen keyboard); the
    /// matching iOS / macOS UI is the testing surface.
    @ViewBuilder
    var apiEndpointsSection: some View {
        #if os(macOS) || os(iOS)
        Section {
            ForEach(APIEndpoint.allCases, id: \.self) { endpoint in
                let binding = Binding<String>(
                    get: { viewModel.endpointURLs[endpoint] ?? endpoint.url },
                    set: { viewModel.endpointURLs[endpoint] = $0 }
                )
                #if os(macOS)
                LabeledContent(endpoint.displayName) {
                    TextField("", text: binding, prompt: Text(endpoint.defaultURL))
                        .onSubmit {
                            viewModel.setEndpointURL(binding.wrappedValue, for: endpoint)
                        }
                        .textFieldStyle(.roundedBorder)
                }
                #else
                VStack(alignment: .leading, spacing: 4) {
                    Text(endpoint.displayName)
                        .font(.system(size: theme.fontSize, weight: .regular))
                    TextField(endpoint.defaultURL, text: binding)
                        .onSubmit {
                            viewModel.setEndpointURL(binding.wrappedValue, for: endpoint)
                        }
                        .font(.system(size: theme.fontSize - 2, weight: .regular))
                        .foregroundStyle(.secondary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                #endif
            }
            if viewModel.hasAnyEndpointOverride {
                Button(role: .destructive) {
                    viewModel.resetAllEndpoints()
                } label: {
                    Text("Reset all to defaults")
                }
            }
        } header: {
            Text("API Endpoints")
        } footer: {
            Text("Override the URLs the app fetches from for testing or routing through a proxy. Press return to apply; changes take effect on next launch. Leave empty (or matching the default) to clear an override.")
        }
        #else
        EmptyView()
        #endif
    }
}

extension SettingsView {
    struct Theme {
        let fontSize: CGFloat = value(tvOS: 38, macOS: 20)
        let hStackSpacing: CGFloat = value(tvOS: 300, macOS: 50)
        var iconLeading: CGFloat { value(tvOS: 100, macOS: 50, compactSize: 0) }
    }
}

/// Detail view for the Auto Select Quality setting, modelled on the
/// iOS Settings → Display → Auto-Lock pattern: a list of every option
/// where each row carries a one-line description of what it does, and
/// a checkmark marks the active selection. Tapping a row commits the
/// choice immediately and dismisses, matching Apple's HIG for
/// settings-style selection screens (no separate "Save" button — the
/// commit is the tap).
struct QualityPickerView: View {
    @Environment(\.dismiss) var dismiss
    /// Local mirror of the stored selection so the UI updates instantly
    /// on tap; we still write through to `Session.autoSelectQuality` so
    /// the change persists.
    @State private var selection: String = Session.autoSelectQuality

    private struct Option: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let description: LocalizedStringKey
    }

    /// Order: Optimal (recommended) first, then Highest, Low,
    /// Selectable. Matches the order in the Settings row's value text
    /// label and the tier ordering in the spec.
    private let options: [Option] = [
        Option(id: "Optimal",
               title: "Optimal",
               description: "Adaptive — picks the best source by composite quality (release tier > resolution > seeds). Recommended."),
        Option(id: "Highest",
               title: "Highest",
               description: "Always picks the highest resolution available. May take longer to start on 4K sources or weak swarms."),
        Option(id: "Low",
               title: "Low",
               description: "Lowest resolution for the fastest start and lowest bandwidth. Useful on slow or metered connections."),
        Option(id: "Selectable",
               title: "Selectable",
               description: "Shows the source picker every time you tap Play, so you can pick the exact release."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        selection = option.id
                        Session.autoSelectQuality = option.id
                        dismiss()
                    } label: {
                        optionRow(option)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("PopcornTime uses this whenever you tap Play. You can override the choice for a single play with long-press / right-click on the Play button.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        #if os(iOS) || os(tvOS)
        .listStyle(GroupedListStyle())
        #endif
    }

    @ViewBuilder
    private func optionRow(_ option: Option) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Apple's selection-list pattern uses a checkmark on the
            // leading edge for the active row and nothing for the rest
            // (no empty circle), so the row's chrome doesn't compete
            // with the description text.
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
                .opacity(selection == option.id ? 1 : 0)
                .frame(width: 18)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.body)
                    .foregroundColor(.primary)
                Text(option.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

struct QualityPickerView_Previews: PreviewProvider {
    static var previews: some View {
        QualityPickerView()
            .preferredColorScheme(.dark)
    }
}
