

import Foundation
import ObjectMapper

private struct Static {
    nonisolated(unsafe) static var movieInstance: WatchlistManager<Movie>? = WatchlistManager<Movie>()
    nonisolated(unsafe) static var showInstance: WatchlistManager<Show>? = WatchlistManager<Show>()
}

typealias jsonArray = [[String : Any]]

/// Class for managing a users watchlist.
open class WatchlistManager<N: Media>: @unchecked Sendable {
    
    private let currentType: Trakt.MediaType
    
    /// Creates new instance of WatchlistManager class with type of Shows.
    public class var show: WatchlistManager<Show> {
        return Static.showInstance!
    }
    
    /// Creates new instance of WatchlistManager class with type of Movies.
    public class var movie: WatchlistManager<Movie> {
        return Static.movieInstance!
    }
    
    fileprivate init?() {
        switch N.self {
        case is Movie.Type:
            currentType = .movies
        case is Show.Type:
            currentType = .shows
        default:
            return nil
        }
    }
    
    /**
     Toggles media in users watchlist and syncs with Trakt if available.
     
     - Parameter media: The media to add or remove.
     */
    open func toggle(_ media: N) {
        isAdded(media) ? remove(media): add(media)
    }
    
    /**
     Adds media to users watchlist and syncs with Trakt if available.
     
     - Parameter media: The media to add.
     */
    open func add(_ media: N) {
        let id = media.id
        let type = currentType
        Task {
            try? await TraktApi.shared.add(id, toWatchlistOfType: type)
        }
        var array = UserDefaults.standard.object(forKey: "\(currentType.rawValue)Watchlist") as? jsonArray ?? jsonArray()
        array.append(Mapper<N>().toJSON(media))
        UserDefaults.standard.set(array, forKey: "\(currentType.rawValue)Watchlist")
    }
    
    /**
     Removes media from users watchlist and syncs with Trakt if available.
     
     - Parameter media: The media to remove.
     */
    open func remove(_ media: N) {
        let id = media.id
        let type = currentType
        Task {
            try? await TraktApi.shared.remove(id, fromWatchlistOfType: type)
        }
        if var array = UserDefaults.standard.object(forKey: "\(currentType.rawValue)Watchlist") as? jsonArray,
            let index = Mapper<N>().mapArray(JSONArray: array).firstIndex(where: { $0.id == media.id }) {
            array.remove(at: index)
            UserDefaults.standard.set(array, forKey: "\(currentType.rawValue)Watchlist")
        }
    }
    
    /**
     Checks media is in the watchlist.
     
     - Parameter media: The media.
     
     - Returns: Boolean indicating if media is in the users watchlist.
     */
    open func isAdded(_ media: N) -> Bool {
        if let array = UserDefaults.standard.object(forKey: "\(currentType.rawValue)Watchlist") as? jsonArray {
            return Mapper<N>().mapArray(JSONArray: array).contains(where: {$0.id == media.id})
        }
        return false
    }
    
    /**
     Gets watchlist locally
     */
    @discardableResult open func getWatchlist() -> [N] {
        let array = UserDefaults.standard.object(forKey: "\(currentType.rawValue)Watchlist") as? jsonArray ?? jsonArray()
        return Mapper<N>().mapArray(JSONArray: array)
    }
    
    /**
     Gets watchlist locally from Trakt if available.
     */
    @discardableResult open func refreshWatchlist() async throws -> [N] {
        let medias = try await TraktApi.shared.getWatchlist(forMediaOfType: N.self)
        UserDefaults.standard.set(Mapper<N>().toJSONArray(medias), forKey: "\(self.currentType.rawValue)Watchlist")
        return medias
    }
}
