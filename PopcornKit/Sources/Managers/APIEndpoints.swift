import Foundation

/// User-overridable registry of public API endpoints the app fetches
/// from. Defaults live alongside each service in
/// `NetworkConfigurations.swift`; this layer adds a UserDefaults-backed
/// override surfaced via Settings → API Endpoints, so a tester can
/// redirect a specific service through a proxy or alternate host
/// without rebuilding.
///
/// Override resolution happens at the first access of each service's
/// `base` constant (Swift `static let` is lazy-initialised once), so
/// changes take effect after the next app launch — the Settings UI
/// makes that explicit in its footer.
public enum APIEndpoint: String, CaseIterable, Sendable {
    case trakt
    case tmdb
    case fanart
    case openSubtitles
    case omdb
    case yts
    case dht

    public var displayName: String {
        switch self {
        case .trakt:         return "Trakt"
        case .tmdb:          return "TMDB"
        case .fanart:        return "Fanart"
        case .openSubtitles: return "OpenSubtitles"
        case .omdb:          return "OMDb (cached)"
        case .yts:           return "YTS"
        case .dht:           return "Mirror discovery (DHT)"
        }
    }

    /// Hard-coded factory default. Mirrors the literal string in
    /// `NetworkConfigurations.swift` for the matching service.
    public var defaultURL: String {
        switch self {
        case .trakt:         return "https://api.trakt.tv"
        case .tmdb:          return "https://api.themoviedb.org/3"
        case .fanart:        return "http://webservice.fanart.tv/v3"
        case .openSubtitles: return "https://api.opensubtitles.com/api/v1/"
        case .omdb:          return "https://reviews.randomrush.work"
        case .yts:           return "https://yts.lt/api/v2"
        case .dht:           return "https://popcorn-dht.8mdm9hjd2h.workers.dev"
        }
    }

    private var key: String { "api.\(rawValue)" }

    /// Active URL — override if set, otherwise factory default.
    public var url: String {
        if let override = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        return defaultURL
    }

    public var isOverridden: Bool {
        guard let v = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !v.isEmpty else { return false }
        return v != defaultURL
    }

    /// Persist an override. Empty / whitespace / equal-to-default
    /// clears the override and restores the factory value.
    public static func setURL(_ url: String?, for endpoint: APIEndpoint) {
        let trimmed = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == endpoint.defaultURL {
            UserDefaults.standard.removeObject(forKey: endpoint.key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: endpoint.key)
        }
    }

    public static func resetAll() {
        for endpoint in allCases {
            UserDefaults.standard.removeObject(forKey: endpoint.key)
        }
    }
}
