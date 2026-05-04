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
import ObjectMapper

extension PopcornApi {

    /// Returns all known Popcorn API mirror base URLs. Tries the DHT worker
    /// first, falls through to a hardcoded mirror list if discovery fails
    /// (the worker currently returns 500s). The cached `Session.popcornBaseUrls`
    /// short-circuits both, but the hardcoded list is unioned in so a single
    /// stale cached URL doesn't strand the user on a dead mirror.
    static func mirrorURLs() async -> [String] {
        var urls: [String] = []
        if let raw = Session.popcornBaseUrls, !raw.isEmpty {
            urls = raw.split(separator: ",").map { cleanURL(String($0)) }
        } else if let endpoints = try? await DHTApi.shared.loadEndpoints(),
                  !endpoints.server.isEmpty,
                  !endpoints.server.contains("Internal Server Error") {
            Session.popcornBaseUrls = endpoints.server
            urls = endpoints.server.split(separator: ",").map { cleanURL(String($0)) }
        }
        // Union with the hardcoded fallbacks so we always probe every known mirror.
        for fallback in Popcorn.fallbackMirrors {
            let cleaned = cleanURL(fallback)
            if !urls.contains(cleaned) { urls.append(cleaned) }
        }
        return urls
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
        // `showAll=1` + `limit=50` mirrors what Popcorn-Desktop 0.5.1 sends so
        // we get the same wider catalog response (un-curated titles included)
        // and the same page size (50 instead of the popcorn-api default 30).
        var params: [String: any Sendable] = [
            "sort": filter.rawValue,
            "order": order.rawValue,
            "genre": genre.rawValue.replacingOccurrences(of: " ", with: "-").lowercased(),
            "limit": 50,
            "showAll": 1,
        ]
        if let searchTerm, !searchTerm.isEmpty {
            params["keywords"] = searchTerm
        }
        let path = Popcorn.movies + "/\(page)"
        let frozenParams = params

        async let popcornResults: [[Movie]] = PopcornApi.aggregate { client in
            try await client.request(.get, path: path, parameters: frozenParams).responseMapable()
        }
        // YTS in parallel: independent index, often surfaces titles the
        // popcorn-api mirrors don't carry.
        async let ytsResult: [Movie]? = try? await YTSApi.shared.loadMovies(
            page: page, filter: filter, genre: genre, searchTerm: searchTerm
        )

        var allLists = await popcornResults
        let ytsList = await ytsResult ?? []
        if !ytsList.isEmpty { allLists.append(ytsList) }

        #if DEBUG
        let popcornCount = allLists.count - (ytsList.isEmpty ? 0 : 1)
        let popcornTotal = allLists.prefix(popcornCount).reduce(0) { $0 + $1.count }
        let ytsTorrentTotal = ytsList.reduce(0) { $0 + $1.torrents.count }
        print("[PopcornTime] loadMovies search=\(searchTerm ?? "-") page=\(page): \(popcornCount) popcorn-mirrors returned \(popcornTotal) movies; YTS returned \(ytsList.count) movies (\(ytsTorrentTotal) torrents)")
        #endif

        guard !allLists.isEmpty else { throw APIError(type: .missingContent) }
        return Movie.merge(allLists)
    }

    open func getMovieInfoAggregated(_ imdbId: String) async throws -> Movie {
        let path = Popcorn.movie + "/\(imdbId)"

        async let popcornResults: [Movie] = PopcornApi.aggregate { client in
            try await client.request(.get, path: path).responseMapable()
        }
        async let ytsResult: Movie? = try? await YTSApi.shared.getMovieInfo(imdbId: imdbId)

        var variants = await popcornResults
        if let yts = await ytsResult {
            variants.append(yts)
        }
        guard let merged = Movie.mergeInfo(variants) else {
            throw APIError(type: .missingContent)
        }
        return merged
    }

    /// Hit `/movie/{imdb_id}/torrents` on every popcorn-api mirror in parallel
    /// and merge with YTS's torrents. This is the dedicated torrent endpoint
    /// Popcorn-Desktop 0.5.1 uses (the bare `/movie/{id}` endpoint returns
    /// metadata-only on most mirrors, with no torrents at all).
    open func getMovieTorrentsAggregated(imdbId: String) async throws -> [Torrent] {
        let path = "\(Popcorn.movie)/\(imdbId)\(Popcorn.movieTorrents)"
        let params: [String: any Sendable] = ["locale": "en", "contentLocale": "en"]
        let frozenParams = params

        async let popcornResults: [[Torrent]] = PopcornApi.aggregate { client in
            let data = try await client.request(.get, path: path, parameters: frozenParams).responseData()
            return PopcornApi.parseTorrentsResponse(data)
        }
        async let ytsTorrents: [Torrent]? = try? await YTSApi.shared.getMovieInfo(imdbId: imdbId).torrents

        var lists = await popcornResults
        let ytsList = await ytsTorrents ?? []
        if !ytsList.isEmpty { lists.append(ytsList) }

        #if DEBUG
        let popcornCount = lists.count - (ytsList.isEmpty ? 0 : 1)
        let popcornTotal = lists.prefix(popcornCount).reduce(0) { $0 + $1.count }
        print("[PopcornTime] getMovieTorrents \(imdbId): popcorn-mirrors=\(popcornCount) returned \(popcornTotal) torrents; YTS=\(ytsList.count) torrents")
        #endif

        return bestTorrents(across: lists)
    }

    /// Hit `/show/{imdb_id}/{season}/{episode}/torrents` on every mirror in
    /// parallel and merge — the same per-episode endpoint Popcorn-Desktop
    /// uses when the user opens a specific episode.
    open func getEpisodeTorrentsAggregated(showImdbId: String, season: Int, episode: Int) async throws -> [Torrent] {
        let path = "\(Popcorn.show)/\(showImdbId)/\(season)/\(episode)\(Popcorn.showTorrents)"
        let params: [String: any Sendable] = ["locale": "en", "contentLocale": "en"]
        let frozenParams = params

        let popcornResults: [[Torrent]] = await PopcornApi.aggregate { client in
            let data = try await client.request(.get, path: path, parameters: frozenParams).responseData()
            return PopcornApi.parseTorrentsResponse(data)
        }
        return bestTorrents(across: popcornResults)
    }

    /// Parse the popcorn-api `/movie/{id}/torrents` (or per-episode) response.
    /// Live mirrors return three different shapes:
    ///
    /// 1. `[ {url, quality, seed, peer, …}, … ]`       array of payloads (most common today),
    /// 2. `{ "en": { "720p": {…}, … }, "ua": {…} }`    locale-keyed (returned by some mirrors),
    /// 3. `{ "720p": {…}, "1080p": {…} }`              flat quality-keyed.
    ///
    /// All locales are unioned and torrents deduped by URL with the highest
    /// seed count winning — exactly the merge logic Movie.init does on
    /// listing responses.
    static func parseTorrentsResponse(_ data: Data) -> [Torrent] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        var collected: [Torrent] = []
        let appendQuality: ([String: [String: Any]]) -> Void = { qualityDict in
            for (quality, payload) in qualityDict {
                guard quality != "0",
                      var t = Torrent(JSON: payload)
                else { continue }
                t.quality = quality
                collected.append(t)
            }
        }

        // Shape 1: flat array of torrent payloads.
        if let array = root as? [[String: Any]] {
            for payload in array {
                guard var t = Torrent(JSON: payload) else { continue }
                if let q = payload["quality"] as? String { t.quality = q }
                collected.append(t)
            }
        } else if let dict = root as? [String: Any] {
            // Shape 2: locale-keyed → quality dicts.
            if let allLocales = dict as? [String: [String: [String: Any]]], !allLocales.isEmpty {
                if let en = allLocales["en"] { appendQuality(en) }
                for (locale, qualities) in allLocales where locale != "en" {
                    appendQuality(qualities)
                }
            }
            // Shape 3: flat quality-keyed.
            if collected.isEmpty, let qualityDict = dict as? [String: [String: Any]] {
                appendQuality(qualityDict)
            }
        }

        var byUrl: [String: Torrent] = [:]
        for t in collected {
            if let existing = byUrl[t.url], existing.seeds >= t.seeds { continue }
            byUrl[t.url] = t
        }
        return Array(byUrl.values).sorted(by: <)
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
            "limit": 50,
            "showAll": 1,
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
