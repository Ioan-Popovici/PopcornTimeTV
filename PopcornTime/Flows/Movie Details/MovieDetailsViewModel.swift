//
//  DetailViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 20.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation
import PopcornKit
import AVKit
import SwiftUI
import Combine

@MainActor
class MovieDetailsViewModel: ObservableObject, CharacterHeadshotLoader, MediaRatingsLoader, MediaPosterLoader {
    @Published var movie: Movie
    @Published var error: Error?
    
    @Published var isLoading = false
    @Published var didLoad = false
    @Published var persons: [Person] = []
    @Published var related: [Movie] = []
    
    var trailerModel: TrailerButtonViewModel
    var downloadModel: DownloadButtonViewModel
    var trailerErrorObserver: AnyCancellable?
    
    init(movie: Movie) {
        self.movie = movie
        self.trailerModel = TrailerButtonViewModel(movie: movie)
        self.downloadModel = DownloadButtonViewModel(media: movie)
        self.trailerErrorObserver = trailerModel.$error.sink(receiveValue: { [unowned self] error in
            self.objectWillChange.send()
        })
    }
    
    func load() {
        guard !isLoading, !didLoad else {
            return
        }
        
        if movie.ratings == nil {
            Task { @MainActor in
                let info = try? await OMDbApi.shared.loadInfo(imdbId: movie.id)
                if let info = info {
                    self.movie.ratings = info.transform()
                }
            }
        }
        
        isLoading = true
        Task { @MainActor in
            do {
                async let related = TraktApi.shared.getRelated(self.movie)
                async let people = TraktApi.shared.getPeople(forMediaOfType: .movies, id: self.movie.id)
                
                // Popcorn-Desktop 0.5.1 doesn't refetch the bare `/movie/{id}`
                // (its `detail()` resolves to `old_data`); it only refreshes
                // torrents via `/movie/{id}/torrents`. We do the same: keep
                // the catalog metadata and union the torrents.
                let freshTorrents = (try? await PopcornKit.getMovieTorrents(movie.id)) ?? []
                let existingUrls = Set(self.movie.torrents.map(\.url))
                let unique = freshTorrents.filter { !existingUrls.contains($0.url) }
                self.movie.torrents = (self.movie.torrents + unique).sorted(by: <)
                self.downloadModel = DownloadButtonViewModel(media: self.movie)
                
                let persons = (try? await people) ?? (actors: [], crew: [])
                self.related = (try? await related) ?? []
                self.persons = persons.actors + persons.crew
                self.movie.actors = persons.actors
                self.movie.crew = persons.crew
                self.didLoad = true
            } catch {
                self.error = error
            }
            self.isLoading = false
        }
    }
    
    var backgroundUrl: URL? {
        return URL(string: movie.largeBackgroundImage ?? "")
    }
    
    func playSongTheme() {
        ThemeSongManager.shared.playMovieTheme(movie.title)
    }
    
    func stopTheme() {
        ThemeSongManager.shared.stopTheme()
    }
}
