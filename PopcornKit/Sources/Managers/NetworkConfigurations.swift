import Foundation

public struct Trakt {
    static let apiKey = "d3b0811a35719a67187cba2476335b2144d31e5840d02f687fbf84e7eaadc811"
    static let apiSecret = "f047aa37b81c87a990e210559a797fd4af3b94c16fb6d22b62aa501ca48ea0a4"
    // Resolved once at first access (Swift `static let` semantics).
    // Override via Settings → API Endpoints; takes effect after restart.
    static let base = APIEndpoint.trakt.url
    static let shows = "/shows"
    static let movies = "/movies"
    static let people = "/people"
    static let person = "/person"
    static let seasons = "/seasons"
    static let episodes = "/episodes"
    static let auth = "/oauth"
    static let token = "/token"
    static let sync = "/sync"
    static let playback = "/playback"
    static let history = "/history"
    static let device = "/device"
    static let code = "/code"
    static let remove = "/remove"
    static let related = "/related"
    static let watched = "/watched"
    static let watchlist = "/watchlist"
    static let scrobble = "/scrobble"
    static let imdb = "/imdb"
    static let tvdb = "/tvdb"
    static let search = "/search"
    
    static let extended = ["extended": "full"]
    public struct Headers {
        static let Default = [
            "Content-Type": "application/json",
            "trakt-api-version": "2",
            "trakt-api-key": Trakt.apiKey
        ]
        
        static func Authorization(_ token: String) -> [String: String] {
            var Authorization = Default; Authorization["Authorization"] = "Bearer \(token)"
            return Authorization
        }
    }
    public enum MediaType: String, Sendable {
        case movies = "movies"
        case shows = "shows"
        case episodes = "episodes"
        case people = "people"
    }
    /**
     Watched status of media.
     
     - .watching:   When the video intially starts playing or is unpaused.
     - .paused:     When the video is paused.
     - .finished:   When the video is stopped or finishes playing on its own.
     */
    public enum WatchedStatus: String, Sendable {
        /// When the video intially starts playing or is unpaused.
        case watching = "start"
        /// When the video is paused.
        case paused = "pause"
        /// When the video is stopped or finishes playing on its own.
        case finished = "stop"
    }
}

public struct TMDB {
    static let apiKey = "ac92176abc89a80e6f5df9510e326601"
    static let base = APIEndpoint.tmdb.url
    static let tv = "/tv"
    static let person = "/person"
    static let images = "/images"
    static let season = "/season"
    static let episode = "/episode"
    static let videos = "/videos"
    
    public enum MediaType: String {
        case movies = "movie"
        case shows = "tv"
    }
    
    static let defaultHeaders = ["api_key": TMDB.apiKey, "language": "en"]
}

public struct Fanart {
    static let apiKey = "bd2753f04538b01479e39e695308b921"
    static let base = APIEndpoint.fanart.url
    static let tv = "/tv"
    static let movies = "/movies"
    
    static let defaultParameters = ["api_key": Fanart.apiKey]
}

public struct OpenSubtitles {
    static let base = APIEndpoint.openSubtitles.url
    static let userAgent = "Popcorn v1"
    static let apiKey = "ljnc55mUqXwU9OZcxC4Hf6ZqJ1WPVMIn"
    static let login = "login"
    static let logout = "logout"
    static let subtitles = "subtitles"
    static let download = "download"
    static let features = "features"
    static let userInfo = "infos/user"
    static let guessit = "utilities/guessit"
    
    // Discovery endpoints
    struct Discover {
        static let popular = "discover/popular"
        static let latest = "discover/latest"
        static let mostDownloaded = "discover/most_downloaded"
    }
    
    static let defaultHeaders = [
        "User-Agent": OpenSubtitles.userAgent,
        "Api-Key": apiKey,
        "Accept": "application/json"
    ]
    
    static func authenticatedHeaders(with bearerToken: String) -> [String: String] {
        var headers = defaultHeaders
        headers["Authorization"] = "Bearer \(bearerToken)"
        headers["Content-Type"] = "application/json"
        return headers
    }
}

//public struct OMDb {
//    static let apiKey = "19f23577"
//    static let base = "http://www.omdbapi.com"
//    static let info = "i"
//
//    static let defaultParameters = ["apikey": OMDb.apiKey]
//}

// cloudflare cached version of above
public struct OMDb {
    static let base = APIEndpoint.omdb.url
    static let info = "i"

    static let defaultParameters: [String: String] = [:]
}

// cloudflare cached version of above
public struct DHT {
    static let base = APIEndpoint.dht.url

    static let defaultParameters: [String: String] = [:]
}

/// YTS — independent direct API for movies. Used as an extra source
/// alongside the Popcorn API mirrors. Magnets are built from the
/// returned info-hash plus the forced-tracker list below.
///
/// As of 2026-05 yts.mx serves the website (HTML), not the JSON API.
/// `yts.lt` and `yts.am` carry the API; the client tries them in order.
public struct YTS {
    /// Override via Settings → API Endpoints prepends a custom host
    /// to the fallback list, so a tester's proxy is tried first while
    /// the canonical mirrors stay as fallbacks.
    static let hosts: [String] = {
        let defaults = [
            "https://yts.lt/api/v2",
            "https://yts.am/api/v2",
            "https://yts.mx/api/v2",
        ]
        let override = APIEndpoint.yts.url
        if APIEndpoint.yts.isOverridden, !defaults.contains(override) {
            return [override] + defaults
        }
        return defaults
    }()
    static let base = hosts[0] // legacy single-host accessor
    static let listMovies = "/list_movies.json"
    static let movieDetails = "/movie_details.json"

    /// Mirrors Popcorn-Desktop 0.5.1's `Settings.trackers.forced` exactly.
    /// Appended to every magnet so peers are discoverable even when the
    /// original .torrent announces are dead.
    /// Source: PopcornTimeDesktop/src/app/settings.js
    static let forcedTrackers: [String] = [
        "udp://tracker.opentrackr.org:1337",
        "udp://tracker.openbittorrent.com:1337",
        "udp://p4p.arenabg.com:1337",
        "udp://exodus.desync.com:6969",
        "udp://tracker.torrent.eu.org:451",
        "udp://tracker-udp.gbitt.info:80",
        "udp://open.stealth.si:80",
        "udp://tracker.dler.org:6969",
        "udp://explodie.org:6969",
        "udp://tracker.therarbg.to:6969",
        "udp://tracker.bittor.pw:1337",
        "udp://tr4ck3r.duckdns.org:6969",
        "wss://tracker.openwebtorrent.com",
    ]
}


public struct Popcorn {
    static let base = "https://uxert.link"

    /// Hardcoded fallback mirror list. The DHT worker
    /// (popcorn-dht.8mdm9hjd2h.workers.dev) currently returns
    /// `{"message":"Internal Server Error"}`, so without this fallback the
    /// app would query a single mirror. These four hosts are the same set
    /// the DHT worker advertised when it was healthy.
    public static let fallbackMirrors: [String] = [
        "https://uxert.link",
        "https://fusme.link",
        "https://jfper.link",
        "https://yrkde.link",
    ]
    static let movies = "/movies"
    static let movie = "/movie"
    static let movieTorrents = "/torrents" // appended after /movie/{id}
    static let shows = "/shows"
    static let show = "/show"
    static let showTorrents = "/torrents" // appended after /show/{id}/{season}/{episode}
    static let status = "/status"
    
    /// Possible orders used in API call.
    public enum Orders: Int {
        case ascending = 1
        case descending = -1
        
    }
    
    /// Possible filters used in API call.
    public enum Filters: String, CaseIterable, Sendable {
        case popularity = "popularity"
        case year = "year"
        case date = "updated"
        case rating = "rating"
        case trending = "trending"
        
        public var string: String {
            switch self {
            case .popularity:
                return "Popular".localized
            case .year:
                return "New".localized
            case .date:
                return "Recently Added".localized
            case .rating:
                return "Top Rated".localized
            case .trending:
                return "Trending".localized
            }
        }
    }
    
    /// Possible genres used in API call.
    public enum Genres: String, Hashable, CaseIterable, Sendable {
        case all = "All"
        case action = "Action"
        case adventure = "Adventure"
        case animation = "Animation"
        case comedy = "Comedy"
        case crime = "Crime"
//        case disaster = "Disaster"
        case documentary = "Documentary"
        case drama = "Drama"
        case family = "Family"
//        case fanFilm = "Fan Film"
        case fantasy = "Fantasy"
//        case filmNoir = "Film Noir"
        case history = "History"
//        case holiday = "Holiday"
        case horror = "Horror"
//        case indie = "Indie"
        case music = "Music"
        case mystery = "Mystery"
//        case road = "Road"
//        case romance = "Romance"
//        case sciFi = "Science Fiction"
//        case short = "Short"
//        case sports = "Sports"
//        case sportingEvent = "Sporting Event"
//        case suspense = "Suspense"
        case thriller = "Thriller"
        case war = "War"
        case western = "Western"
        
        public var string: String {
            return rawValue.localized
        }
    }
    
    struct APIError: Decodable, Error, LocalizedError {
        var message: String
        var code: Int
        
        public var errorDescription: String? {
            return "\(message) - \(code)"
        }
    }
}
