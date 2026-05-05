//
//  SettingsViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 31.07.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
import Network

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var clearCache = ClearCache()
    
    @Published var isTraktLoggedIn: Bool = TraktSession.shared.isLoggedIn()
    var traktAuthorizationUrl: URL {
        return TraktAuthApi.shared.authorizationUrl(appScheme: AppScheme)
    }
    
    // MARK: - OpenSubtitles
    @Published var isOpenSubtitlesLoggedIn: Bool = SubtitlesApi.shared.isLoggedIn
    @Published var isOpenSubtitlesLoading: Bool = false
    @Published var openSubtitlesLoginError: String?
    
    var lastUpdate: String {
        var date = "Never".localized
        if let lastChecked = Session.lastVersionCheckPerformedOnDate {
            date = DateFormatter.localizedString(from: lastChecked, dateStyle: .short, timeStyle: .short)
        }
        return date
    }
    
    var version: String {
        let bundle = Bundle.main
        return [bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString"), bundle.object(forInfoDictionaryKey: "CFBundleVersion")].compactMap({$0 as? String}).joined(separator: ".")
    }
    
    func validate(traktUrl: URL) {
        if traktUrl.scheme?.lowercased() == AppScheme.lowercased() {
            Task { @MainActor in
                try await TraktAuthApi.shared.authenticate(traktUrl)
                self.traktDidLoggedIn()
            }
        }
    }
    
    func traktLogout() {
        TraktSession.shared.logout()
        isTraktLoggedIn = false
    }
    
    func traktDidLoggedIn() {
        isTraktLoggedIn = true
        TraktApi.shared.syncUserData()
    }
    
    // MARK: - OpenSubtitles Methods
    func openSubtitlesLogin(username: String, password: String) {
        guard !username.isEmpty && !password.isEmpty else { return }
        
        isOpenSubtitlesLoading = true
        openSubtitlesLoginError = nil
        
        Task { @MainActor in
            do {
                _ = try await SubtitlesApi.shared.login(username: username, password: password)
                self.isOpenSubtitlesLoggedIn = true
                self.openSubtitlesLoginError = nil
            } catch {
                self.openSubtitlesLoginError = error.localizedDescription
                // Keep the dialog open by not changing the login state
                // The error message will be displayed in the dialog
            }
            self.isOpenSubtitlesLoading = false
        }
    }
    
    func openSubtitlesLogout() {
        self.isOpenSubtitlesLoading = true
        Task { @MainActor in
            do {
                try await SubtitlesApi.shared.logout()
            } catch {
                print("OpenSubtitles logout error: \(error)")
            }
            self.isOpenSubtitlesLoggedIn = false
            self.isOpenSubtitlesLoading = false
        }
    }
    
    @Published var serverUrl: String = PopcornKit.serverURL()
    var chekServerIsUpTask: Task<(), Never>?

    func changeUrl(_ url: String) {
        self.chekServerIsUpTask?.cancel()
        self.chekServerIsUpTask = Task { @MainActor [weak self] in
            self?.serverUrl = await PopcornKit.setUserCustomUrls(newUrl: url)
            self?.chekServerIsUpTask = nil
        }
    }

    // MARK: - Popcorn server list
    //
    // The list-style UI (System Settings → Network → DNS shape: rows
    // with `+` / `-` controls + a Restore Defaults button) operates on
    // an in-memory `[String]`. `PopcornKit.serverURL()` /
    // `setUserCustomUrls(_:)` keep the comma-separated string format
    // for back-compat with the existing fetch path; we just convert
    // at the boundary.

    @Published var popcornUrls: [String] = SettingsViewModel.parsePopcornUrls(PopcornKit.serverURL())
    @Published var newPopcornUrl: String = ""

    private static func parsePopcornUrls(_ joined: String) -> [String] {
        joined
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func commitPopcornUrls() {
        let joined = popcornUrls.joined(separator: ",")
        chekServerIsUpTask?.cancel()
        chekServerIsUpTask = Task { @MainActor [weak self] in
            let resolved = await PopcornKit.setUserCustomUrls(newUrl: joined)
            self?.serverUrl = resolved
            self?.popcornUrls = SettingsViewModel.parsePopcornUrls(resolved)
            self?.chekServerIsUpTask = nil
        }
    }

    func addPopcornUrl() {
        let trimmed = newPopcornUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !popcornUrls.contains(trimmed) else { return }
        popcornUrls.append(trimmed)
        newPopcornUrl = ""
        commitPopcornUrls()
    }

    func removePopcornUrls(at offsets: IndexSet) {
        popcornUrls.remove(atOffsets: offsets)
        commitPopcornUrls()
    }

    func removePopcornUrl(_ url: String) {
        popcornUrls.removeAll(where: { $0 == url })
        commitPopcornUrls()
    }

    func restorePopcornUrlDefaults() {
        popcornUrls = Popcorn.fallbackMirrors
        commitPopcornUrls()
    }

    // MARK: - API endpoint overrides
    //
    // Each entry holds the in-flight value of the field while the
    // user types. Persistence happens on field commit (`onSubmit`)
    // via `setEndpointURL(_:for:)` — the active service URL is
    // resolved at first access of `<Service>.base`, so changes take
    // effect on next app launch (footer copy makes that explicit).

    @Published var endpointURLs: [APIEndpoint: String] = {
        var dict: [APIEndpoint: String] = [:]
        for ep in APIEndpoint.allCases {
            dict[ep] = ep.url
        }
        return dict
    }()

    func setEndpointURL(_ url: String, for endpoint: APIEndpoint) {
        APIEndpoint.setURL(url, for: endpoint)
        endpointURLs[endpoint] = endpoint.url
    }

    func resetAllEndpoints() {
        APIEndpoint.resetAll()
        for endpoint in APIEndpoint.allCases {
            endpointURLs[endpoint] = endpoint.url
        }
    }

    var hasAnyEndpointOverride: Bool {
        APIEndpoint.allCases.contains(where: { $0.isOverridden })
    }
    
    var networkMonitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: .global())
        return monitor
    }()
    
    var hasCellularNetwork: Bool {
        return networkMonitor.currentPath.availableInterfaces.contains(where: {$0.type == .cellular }) || networkMonitor.currentPath.isExpensive
    }
}
