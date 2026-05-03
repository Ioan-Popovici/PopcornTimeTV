//
//  File.swift
//  
//
//  Created by Alexandru Tudose on 18.12.2021.
//

import Foundation
import SwiftyJSON

open class FanartApi: @unchecked Sendable {
    /// Creates new instance of FanArtApi class
    public static let shared = FanartApi()
    
    let client = HttpClient(config: .init(serverURL: Fanart.base))
    
    
    /**
     Load Movie or TV Show logos from Fanart.tv.
     
     - Parameter forMediaOfType:    The type of the media. Only available for movies and shows.
     - Parameter id:                The imdb id of the movie or the tvdb id of the show.
     */
    open func getLogo(forMediaOfType type: Trakt.MediaType, id: String) async throws -> String {
        let path = (type == .movies ? Fanart.movies : Fanart.tv) + "/\(id)"
        let data = try await client.request(.get, path: path, parameters: Fanart.defaultParameters).responseData()
        let responseDict = JSON(data)
        
        let typeString = type == .movies ? "movie" : "tv"
        let image = responseDict["hd\(typeString)logo"].first(where: { $0.1["lang"].string == "en" })?.1["url"].string
        return image ?? ""
    }
}
   
