//
//  Ratings.swift
//  
//
//  Created by Alexandru Tudose on 25.09.2021.
//

import Foundation

public struct Ratings: Equatable, Sendable {
    public var awards: String?
    public var imdbRating: String?
    public var metascore: String?
    public var rottenTomatoes: String?
    
    public init(awards: String?, imdbRating: String?, metascore: String?, rottenTomatoes: String?) {
        self.awards = awards != "N/A" ? awards : nil
        self.imdbRating = imdbRating != "N/A" ? imdbRating : nil
        self.metascore = metascore != "N/A" ? metascore : nil
        self.rottenTomatoes = rottenTomatoes
    }
    
    public var hasValue: Bool {
        return imdbRating != nil || metascore != nil || rottenTomatoes != nil
    }
}

extension Media {
    public var imdbUrl: URL {
        return URL(string:"https://www.imdb.com/title/\(id)") ?? URL(string: "")!
    }
    
    public var rottentomatoesUrl: URL {
        return URL(string:"https://www.rottentomatoes.com/search?search=\(slug)") ?? URL(string: "")!
    }
}

extension Movie {
    public var metacriticFindUrl: URL {
        return URL(string:"https://www.metacritic.com/search/movie/\(slug)/results") ?? URL(string: "")!
    }
    public var metacriticUrl: URL {
        return URL(string:"https://www.metacritic.com/movie/\(slug)") ?? URL(string: "")!
    }
}

extension Show {
    public var metacriticFindUrl: URL {
        return URL(string:"https://www.metacritic.com/search/show/\(slug)/results") ?? URL(string: "")!
    }
    public var metacriticUrl: URL {
        return URL(string:"https://www.metacritic.com/show/\(slug)") ?? URL(string: "")!
    }
}
