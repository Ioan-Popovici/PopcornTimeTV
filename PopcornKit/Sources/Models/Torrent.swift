

import Foundation
import ObjectMapper

/**
 Health of a torrent.
 */
public enum Health: Sendable {
    /// Low number of seeds and peers.
    case bad
    /// Moderate number of seeds and peers.
    case medium
    /// Lots of seeds and peers.
    case good
    /// Fucking lots of seeds and peers.
    case excellent
    /// Health of the torrent cannot be calcualted.
    case unknown
    
    public var name: String {
        switch self {
        case .bad:
            return "bad"
        case .medium:
            return "medium"
        case .good:
            return "good"
        case .excellent:
            return "excellent"
        case .unknown:
            return "unknow"
        }
    }
}

public struct Torrent: Mappable, Equatable, Comparable, Sendable {
    
    /// Health of the torrent.
    public let health: Health
    
    /// Url of the torrent. May be http url or may be a magnet link.
    public let url: String
    
    /// Quality of the media - 1080p, 720p, 480p etc.
    public var quality: String!
    
    /// Number of seeds the torrent has.
    public let seeds: Int
    
    /// Number of peers the torrent has.
    public let peers: Int
    
    /// Size of the torrent. Will be `nil` if object is episode.
    public let size: String?

    /// Content locale this torrent was tagged under by the popcorn-api
    /// response (e.g. "en", "ru", "ua", "fr"). Used to honour the user's
    /// preferred audio-language when the picker auto-selects a torrent.
    /// `nil` for torrents that came from a source without locale tagging
    /// (e.g. YTS — whose catalogue is English-original by default).
    public var locale: String?

    public init?(map: Map) {
        do { self = try Torrent(map) }
        catch { return nil }
    }
    
    private init(_ map: Map) throws {
        let rawUrl: String = try map.value("url")
        self.url = Torrent.augmentMagnetWithForcedTrackers(rawUrl)
        self.seeds = (try? (try? map.value("seeds")) ?? map.value(("seed"))) ?? 0
        self.peers = (try? (try? map.value("peers")) ?? map.value(("peer"))) ?? 0
        self.size = try? map.value("filesize")
        self.quality = try? map.value("quality") // Will only not be `nil` if object is mapped from JSON array, otherwise this is set in `Show or Movie` struct.
        
        // First calculate the seed/peer ratio
        let ratio = peers > 0 ? (seeds / peers) : seeds
        
        // Normalize the data. Convert each to a percentage
        // Ratio: Anything above a ratio of 5 is good
        let normalizedRatio = min(ratio / 5 * 100, 100)
        // Seeds: Anything above 30 seeds is good
        let normalizedSeeds = min(seeds / 30 * 100, 100)
        
        // Weight the above metrics differently
        // Ratio is weighted 60% whilst seeders is 40%
        let weightedRatio = Double(normalizedRatio) * 0.6
        let weightedSeeds = Double(normalizedSeeds) * 0.4
        let weightedTotal = weightedRatio + weightedSeeds
        
        // Scale from [0, 100] to [0, 3]. Drops the decimal places
        var scaledTotal = ((weightedTotal * 3.0) / 100.0)// | 0.0
        if scaledTotal < 0 { scaledTotal = 0 }
        
        switch floor(scaledTotal) {
        case 0:
            health = .bad
        case 1:
            health = .medium
        case 2:
            health = .good
        case 3:
            health = .excellent
        default:
            health = .unknown
        }
    }
    
    public init(health: Health = .unknown, url: String = "", quality: String = "0p", seeds: Int = 0, peers: Int = 0, size: String? = nil, locale: String? = nil) {
        self.health = health
        self.url = Torrent.augmentMagnetWithForcedTrackers(url)
        self.quality = quality
        self.seeds = seeds
        self.peers = peers
        self.size = size
        self.locale = locale
    }

    /// Decorate a magnet URI with the same forced-tracker list
    /// Popcorn-Desktop appends, deduped and `&amp;`-decoded. Many
    /// popcorn-api magnets in the wild ship with only 1–3 trackers
    /// (sometimes locale-specific, e.g. `bt.toloka.to` for Ukrainian
    /// uploads), and libtorrent then has to do peer discovery via DHT
    /// alone — slow first chunks. Pre-loading the magnet with the same
    /// 13 trackers the desktop client uses makes peer discovery
    /// essentially instant.
    static func augmentMagnetWithForcedTrackers(_ rawUrl: String) -> String {
        guard rawUrl.lowercased().hasPrefix("magnet:") else { return rawUrl }
        // Some sources HTML-encode `&` as `&amp;` inside the magnet URL
        // (we saw this on uxert.link). Normalise so trackers parse.
        let normalized = rawUrl.replacingOccurrences(of: "&amp;", with: "&")

        // Collect existing tracker hosts so we don't add duplicates.
        var existing: Set<String> = []
        for component in normalized.split(separator: "&") {
            guard component.hasPrefix("tr=") else { continue }
            let value = String(component.dropFirst(3))
            if let decoded = value.removingPercentEncoding {
                existing.insert(Self.trackerKey(decoded))
            }
        }

        var result = normalized
        for tracker in YTS.forcedTrackers {
            if existing.contains(Self.trackerKey(tracker)) { continue }
            let encoded = tracker.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tracker
            result += "&tr=" + encoded
            existing.insert(Self.trackerKey(tracker))
        }
        return result
    }

    /// Compare trackers by host:port (ignore `/announce` suffix etc.) so
    /// we don't double-add the same tracker that's already on the magnet
    /// in a slightly different form.
    private static func trackerKey(_ tracker: String) -> String {
        var t = tracker
        if let q = t.firstIndex(of: "?") { t = String(t[..<q]) }
        if t.hasSuffix("/announce") { t = String(t.dropLast("/announce".count)) }
        if t.hasSuffix("/") { t = String(t.dropLast()) }
        return t.lowercased()
    }
    
    public mutating func mapping(map: Map) {
        switch map.mappingType {
        case .fromJSON:
            if let torrent = Torrent(map: map) {
                self = torrent
            }
            
        case .toJSON:
            url >>> map["url"]
            seeds >>> map["seeds"]
            peers >>> map["peers"]
            quality >>> map["quality"]
            size >>> map["filesize"]
        }
    }
}

public func >(lhs: Torrent, rhs: Torrent) -> Bool {
    if let lhsSize = lhs.quality, let rhsSize = rhs.quality {
        if lhsSize.count == 2  && rhsSize.count > 2 // 3D
        {
            return true
        } else if lhsSize.count == 5 && rhsSize.count < 5 && rhsSize.count > 2 // 1080p
        {
            return true
        } else if lhsSize.count == 4 && rhsSize.count == 4 // 720p and 480p
        {
            return lhsSize > rhsSize
        }
    }
    return false
}

public func <(lhs: Torrent, rhs: Torrent) -> Bool {
    if let lhsSize = lhs.quality, let rhsSize = rhs.quality {
        if rhsSize.count == 2  && lhsSize.count > 2 // 3D
        {
            return true
        } else if rhsSize.count == 5 && lhsSize.count < 5 && lhsSize.count > 2 // 1080p
        {
            return true
        } else if rhsSize.count == 4 && lhsSize.count == 4 // 720p and 480p
        {
            return lhsSize < rhsSize
        }
    }
    return false
}

extension Torrent: Identifiable {
    public var id: String {
        return url
    }
}

public func == (lhs: Torrent, rhs: Torrent) -> Bool {
    return lhs.url == rhs.url
}
