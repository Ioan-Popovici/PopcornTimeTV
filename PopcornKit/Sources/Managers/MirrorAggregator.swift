//
//  MirrorAggregator.swift
//  PopcornKit
//
//  Fans every Popcorn API request out across all known mirrors in parallel
//  and merges the responses: dedup-by-IMDb-ID for catalog listings, and
//  union-by-URL for torrents (keeping the highest seed count). The DHT
//  worker advertises multiple independently-operated mirrors, each with its
//  own torrent index — querying just one (the previous behaviour) yielded
//  fewer titles and lower S/P than the full network can offer.
//

import Foundation

extension PopcornApi {

    /// Returns all known Popcorn API mirror base URLs. On first call (or
    /// when the cache is empty), discovers them from the DHT worker.
    static func mirrorURLs() async -> [String] {
        if let raw = Session.popcornBaseUrls, !raw.isEmpty {
            return raw.split(separator: ",").map { cleanURL(String($0)) }
        }
        if let endpoints = try? await DHTApi.shared.loadEndpoints() {
            Session.popcornBaseUrls = endpoints.server
            return endpoints.server.split(separator: ",").map { cleanURL(String($0)) }
        }
        return [cleanURL(Popcorn.base)]
    }

    private static func cleanURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private static func mirrorClient(for baseURL: String) -> HttpClient {
        HttpClient(config: .init(serverURL: baseURL, apiErrorDecoder: { data in
            try? JSONDecoder().decode(Popcorn.APIError.self, from: data)
        }))
    }

    /// Run `work` against every mirror in parallel, returning every
    /// successful response. Mirrors that fail or time out are silently
    /// dropped — partial results still expand the catalogue.
    private static func aggregate<T: Sendable>(
        _ work: @Sendable @escaping (HttpClient) async throws -> T
    ) async -> [T] {
        let urls = await mirrorURLs()
        return await withTaskGroup(of: T?.self) { group in
            for baseURL in urls {
                group.addTask {
                    try? await work(mirrorClient(for: baseURL))
                }
            }
            var results: [T] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }
    }

    // MARK: - Movies

    open func loadMoviesAggregated(
        _ page: Int,
        filterBy filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        orderBy order: Popcorn.Orders
    ) async throws -> [Movie] {
        var params: [String: any Sendable] = [
            "sort": filter.rawValue,
            "order": order.rawValue,
            "genre": genre.rawValue.replacingOccurrences(of: " ", with: "-").lowercased(),
        ]
        if let searchTerm, !searchTerm.isEmpty {
            params["keywords"] = searchTerm
        }
        let path = Popcorn.movies + "/\(page)"
        let frozenParams = params
        let results: [[Movie]] = await PopcornApi.aggregate { client in
            try await client.request(.get, path: path, parameters: frozenParams).responseMapable()
        }
        guard !results.isEmpty else { throw APIError(type: .missingContent) }
        return Movie.merge(results)
    }

    open func getMovieInfoAggregated(_ imdbId: String) async throws -> Movie {
        let path = Popcorn.movie + "/\(imdbId)"
        let results: [Movie] = await PopcornApi.aggregate { client in
            try await client.request(.get, path: path).responseMapable()
        }
        guard let merged = Movie.mergeInfo(results) else {
            throw APIError(type: .missingContent)
        }
        return merged
    }

    // MARK: - Shows

    open func loadShowsAggregated(
        _ page: Int,
        filterBy filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        orderBy order: Popcorn.Orders
    ) async throws -> [Show] {
        var params: [String: any Sendable] = [
            "sort": filter.rawValue,
            "genre": genre.rawValue.replacingOccurrences(of: " ", with: "-").lowercased(),
            "order": order.rawValue,
        ]
        if let searchTerm, !searchTerm.isEmpty {
            params["keywords"] = searchTerm
        }
        let path = Popcorn.shows + "/\(page)"
        let frozenParams = params
        let results: [[Show]] = await PopcornApi.aggregate { client in
            try await client.request(.get, path: path, parameters: frozenParams).responseMapable()
        }
        guard !results.isEmpty else { throw APIError(type: .missingContent) }
        return Show.merge(results)
    }

    open func getShowInfoAggregated(_ imdbId: String) async throws -> Show {
        let path = Popcorn.show + "/\(imdbId)"
        let results: [Show] = await PopcornApi.aggregate { client in
            try await client.request(.get, path: path).responseMapable()
        }
        guard let merged = Show.mergeInfo(results) else {
            throw APIError(type: .missingContent)
        }
        return merged
    }
}

// MARK: - Merging

extension Movie {
    /// Pick the variant with the most torrents as canonical metadata, then
    /// union torrents across every variant.
    static func mergeInfo(_ variants: [Movie]) -> Movie? {
        guard let canonical = variants.max(by: { $0.torrents.count < $1.torrents.count }) else {
            return nil
        }
        var merged = canonical
        merged.torrents = bestTorrents(across: variants.map(\.torrents))
        return merged
    }

    /// Merge catalogue pages from multiple mirrors. Order: first mirror's
    /// ordering wins; unique additions from later mirrors are appended.
    static func merge(_ lists: [[Movie]]) -> [Movie] {
        var byIdGroups: [String: [Movie]] = [:]
        var order: [String] = []
        for list in lists {
            for movie in list {
                if byIdGroups[movie.id] == nil { order.append(movie.id) }
                byIdGroups[movie.id, default: []].append(movie)
            }
        }
        return order.compactMap { id in mergeInfo(byIdGroups[id] ?? []) }
    }
}

extension Show {
    static func mergeInfo(_ variants: [Show]) -> Show? {
        guard let canonical = variants.max(by: { $0.episodes.count < $1.episodes.count }) else {
            return nil
        }
        var merged = canonical
        struct EpisodeKey: Hashable { let season: Int; let episode: Int }
        var byEpisode: [EpisodeKey: [Episode]] = [:]
        for variant in variants {
            for ep in variant.episodes {
                byEpisode[EpisodeKey(season: ep.season, episode: ep.episode), default: []].append(ep)
            }
        }
        merged.episodes = byEpisode.values
            .compactMap(Episode.mergeTorrents)
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        return merged
    }

    static func merge(_ lists: [[Show]]) -> [Show] {
        var byIdGroups: [String: [Show]] = [:]
        var order: [String] = []
        for list in lists {
            for show in list {
                if byIdGroups[show.id] == nil { order.append(show.id) }
                byIdGroups[show.id, default: []].append(show)
            }
        }
        return order.compactMap { id in mergeInfo(byIdGroups[id] ?? []) }
    }
}

extension Episode {
    static func mergeTorrents(_ variants: [Episode]) -> Episode? {
        guard var canonical = variants.first else { return nil }
        canonical.torrents = bestTorrents(across: variants.map(\.torrents))
        return canonical
    }
}

/// Union torrents across mirrors, dedup by URL, keep the variant with the
/// most seeds (best torrent health) when the same URL appears more than once.
private func bestTorrents(across lists: [[Torrent]]) -> [Torrent] {
    var byUrl: [String: Torrent] = [:]
    for list in lists {
        for torrent in list {
            if let existing = byUrl[torrent.url], existing.seeds >= torrent.seeds { continue }
            byUrl[torrent.url] = torrent
        }
    }
    return Array(byUrl.values).sorted(by: <)
}
