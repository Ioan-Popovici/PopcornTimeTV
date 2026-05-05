//
//  ContentProvider.swift
//  TopShelfSwiftUI
//
//  Created by Alexandru Tudose on 06.07.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

@preconcurrency import TVServices
import PopcornKit
import ObjectMapper

class ContentProvider: TVTopShelfContentProvider {

    override open func loadTopShelfContent() async -> TVTopShelfContent? {
        
        let movies = try? await PopcornKit.loadMovies(filterBy: .trending)
        let movieItems = movies?.prefix(10).map{ self.mapMedia($0) } ?? []
        let movieSection = TVTopShelfItemCollection(items: movieItems)
        movieSection.title = "Trending Movies"
        
        let shows = try? await PopcornKit.loadShows(filterBy: .trending)
        let showItems = shows?.prefix(10).map{ self.mapMedia($0) } ?? []
        let showSection = TVTopShelfItemCollection(items: showItems)
        showSection.title = "Trending Shows"
        
        return TVTopShelfSectionedContent(sections: [
            movieSection,
            showSection
        ])
    }
    
    func mapMedia(_ media: Media) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: media.id)
        item.title = media.title
        item.setImageURL(URL(string: media.mediumCoverImage ?? ""), for: .screenScale1x)
        item.setImageURL(URL(string: media.mediumCoverImage ?? ""), for: .screenScale2x)
        item.imageShape = .poster
//        item.playbackProgress = Double(WatchedlistManager<Movie>.movie.currentProgress(media.id))

        // generate url
        var components = URLComponents()
        components.scheme = AppScheme
        components.queryItems = [URLQueryItem(name: "action", value: toJSONString(media))]
        if let url = components.url {
            item.playAction = TVTopShelfAction(url: url)
            item.displayAction = TVTopShelfAction(url: url)
        }
        
        
        return item
    }
    
    func toJSONString(_ media: Media) -> String {
        switch media {
        case is Movie:
            return "showMovie" + "»" + (media.toJSONString() ?? "")
        case is Show:
            return "showShow" + "»" + (media.toJSONString() ?? "")
        default:
            return ""
        }
    }
}

