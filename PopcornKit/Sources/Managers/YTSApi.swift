//
//  YTSApi.swift
//  PopcornKit
//
//  YTS (yts.mx/api/v2) is an independent movie index — the same direct
//  fallback Popcorn-Desktop 0.5.1 ships in `butter-provider/yts.js`. It is
//  not a popcorn-api mirror; it has its own catalog, torrents, and
//  infohashes. Adding it to the aggregator widens the set of titles the
//  app can find.
//
//  YTS responses are remapped into popcorn-api's JSON shape and run
//  through ObjectMapper, so they end up as ordinary `Movie` values
//  indistinguishable from the Popcorn API mirrors at the call site.
//

import Foundation
import ObjectMapper

open class YTSApi: @unchecked Sendable {
    public static let shared = YTSApi()

    /// Per-host clients; we try them in order until one returns a usable
    /// response. yts.mx now serves HTML; yts.lt and yts.am still serve the
    /// JSON API.
    private let clients: [HttpClient] = YTS.hosts.map { HttpClient(config: HttpApiConfig(serverURL: $0)) }
    let client = HttpClient(config: HttpApiConfig(serverURL: YTS.base)) // legacy single-host

    private func firstWorkingResponse<T: Decodable>(
        _ work: (HttpClient) async throws -> T
    ) async throws -> T {
        var lastError: Error = APIError(type: .missingContent)
        for client in clients {
            do {
                return try await work(client)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    public func loadMovies(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?
    ) async throws -> [Movie] {
        var params: [String: any Sendable] = [
            "page": page,
            "limit": 50,
            "sort_by": Self.ytsSortBy(for: filter),
            "order_by": "desc",
        ]
        if genre != .all {
            params["genre"] = genre.rawValue.lowercased()
        }
        if let searchTerm, !searchTerm.isEmpty {
            params["query_term"] = searchTerm
        }
        let frozenParams = params
        let response: YTSListMoviesResponse = try await firstWorkingResponse { client in
            try await client.request(.get, path: YTS.listMovies, parameters: frozenParams).responseDecode()
        }
        return (response.data.movies ?? []).compactMap { $0.toPopcornMovie() }
    }

    public func getMovieInfo(imdbId: String) async throws -> Movie {
        // Try movie_details.json first (the dedicated detail endpoint).
        let detailParams: [String: any Sendable] = [
            "imdb_id": imdbId,
            "with_images": "true",
            "with_cast": "false",
        ]
        if let response: YTSMovieDetailsResponse = try? await firstWorkingResponse({ client in
            try await client.request(.get, path: YTS.movieDetails, parameters: detailParams).responseDecode()
        }),
           let movie = response.data.movie?.toPopcornMovie(),
           !movie.torrents.isEmpty {
            return movie
        }
        // Fallback: list_movies.json with the IMDb id as the query term. Some
        // movies are findable via list_movies but not movie_details (and vice
        // versa). list_movies is also the endpoint that consistently returns
        // torrents inline.
        let listParams: [String: any Sendable] = [
            "query_term": imdbId,
            "limit": 1,
        ]
        let listResponse: YTSListMoviesResponse = try await firstWorkingResponse { client in
            try await client.request(.get, path: YTS.listMovies, parameters: listParams).responseDecode()
        }
        guard let movie = listResponse.data.movies?.first?.toPopcornMovie() else {
            throw APIError(type: .missingContent)
        }
        return movie
    }

    private static func ytsSortBy(for filter: Popcorn.Filters) -> String {
        switch filter {
        case .popularity: return "download_count"
        case .year:       return "year"
        case .date:       return "date_added"
        case .rating:     return "rating"
        case .trending:   return "like_count"
        }
    }
}

// MARK: - YTS response shapes

private struct YTSListMoviesResponse: Decodable {
    struct Data: Decodable { let movies: [YTSMovie]? }
    let data: Data
}

private struct YTSMovieDetailsResponse: Decodable {
    struct Data: Decodable { let movie: YTSMovie? }
    let data: Data
}

private struct YTSMovie: Decodable {
    let id: Int?
    let imdb_code: String?
    let title: String?
    let title_long: String?
    let slug: String?
    let year: Int?
    let rating: Double?
    let runtime: Int?
    let genres: [String]?
    let summary: String?
    let synopsis: String?
    let description_full: String?
    let yt_trailer_code: String?
    let mpa_rating: String?
    let background_image: String?
    let background_image_original: String?
    let small_cover_image: String?
    let medium_cover_image: String?
    let large_cover_image: String?
    let torrents: [YTSTorrent]?

    /// Translate the YTS payload into the JSON shape `Movie(map:)` expects, then
    /// hand it to ObjectMapper. This avoids forking the Movie struct just to
    /// accept an alternative source.
    func toPopcornMovie() -> Movie? {
        guard let imdbId = imdb_code, !imdbId.isEmpty else { return nil }
        let resolvedTitle = title ?? title_long ?? ""
        guard !resolvedTitle.isEmpty else { return nil }

        let summary = (summary ?? synopsis ?? description_full ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trailerUrl = yt_trailer_code.map { "https://www.youtube.com/watch?v=\($0)" } ?? ""

        var torrentsByQuality: [String: [String: Any]] = [:]
        for t in (torrents ?? []) {
            let quality = t.quality ?? "0p"
            torrentsByQuality[quality] = t.toPopcornTorrentJSON(displayName: slug ?? resolvedTitle)
        }

        let json: [String: Any] = [
            "imdb_id": imdbId,
            "title": resolvedTitle,
            "year": year.map(String.init) ?? "",
            "rating": ["percentage": (rating ?? 0) * 10],
            "runtime": runtime ?? 0,
            "synopsis": summary,
            "slug": slug ?? imdbId,
            "certification": mpa_rating ?? "",
            "genres": (genres ?? []).map { $0.lowercased() },
            "trailer": trailerUrl,
            "images": [
                "poster": large_cover_image ?? medium_cover_image ?? small_cover_image ?? "",
                "fanart": background_image_original ?? background_image ?? "",
            ],
            "torrents.en": torrentsByQuality,
        ]
        return Mapper<Movie>().map(JSON: flattenedTorrents(json))
    }

    /// ObjectMapper interprets nested keys like `torrents.en` as a path lookup,
    /// so we have to physically nest the torrents under `torrents`/`en` rather
    /// than use a single literal key.
    private func flattenedTorrents(_ source: [String: Any]) -> [String: Any] {
        var out = source
        if let inner = out.removeValue(forKey: "torrents.en") {
            out["torrents"] = ["en": inner]
        }
        return out
    }
}

private struct YTSTorrent: Decodable {
    let url: String?
    let hash: String?
    let quality: String?
    let type: String?
    let seeds: Int?
    let peers: Int?
    let size: String?
    let size_bytes: Int64?

    /// Build the popcorn-api-shaped torrent dict. The `url` is a fully formed
    /// magnet (info-hash + display-name + 13 forced trackers) rather than the
    /// http download link YTS returns directly, so playback works without
    /// hitting yts.mx during preroll.
    func toPopcornTorrentJSON(displayName: String) -> [String: Any] {
        var dict: [String: Any] = [
            "url": magnet(displayName: displayName),
            "seeds": seeds ?? 0,
            "peers": peers ?? 0,
        ]
        if let size = size, !size.isEmpty {
            dict["filesize"] = size
        }
        return dict
    }

    private func magnet(displayName: String) -> String {
        let infoHash = (hash ?? "").lowercased()
        let dn = displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? displayName
        let trackers = YTS.forcedTrackers
            .compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }
            .map { "tr=\($0)" }
            .joined(separator: "&")
        return "magnet:?xt=urn:btih:\(infoHash)&dn=\(dn)&\(trackers)"
    }
}
