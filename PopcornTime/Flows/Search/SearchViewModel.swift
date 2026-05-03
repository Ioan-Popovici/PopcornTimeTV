//
//  SearchViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 27.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    enum SearchType: Int {
        case movies = 0, shows, people
    }
    
    @Published var search = ""
    @Published var selection: SearchType = .movies
    @Published var isLoading = false
    
    @Published var movies: [Movie] = []
    @Published var shows: [Show] = []
    @Published var persons: [Person] = []
    @Published var error: Error?
    var onTextChange: AnyCancellable?
    
    init() {
        self.onTextChange = Publishers.CombineLatest($search, $selection)
            .removeDuplicates { prev, curent in
                let isSame = prev == curent
                if !isSame && curent.0.count > 2 {
                    self.isLoading = true
                    self.error = nil
                }
                return isSame
            }
            .debounce(for: 1.5, scheduler: RunLoop.main)
            .sink(receiveValue: { [weak self] value in
                self?.filterSearchText(value.0)
        })
    }
    
    func filterSearchText(_ text: String) {
        guard text.count > 2 else {
            isLoading = false
            persons = []
            movies = []
            shows = []
            return
        }
        
        isLoading = true
        persons = []
        movies = []
        shows = []
        error = nil

        Task { @MainActor in
            do  {
                switch selection {
                case .movies:
                    self.movies = try await PopcornKit.loadMovies(searchTerm: text)
                case .shows:
                    self.shows = try await PopcornKit.loadShows(searchTerm: text)
                case .people:
                    self.persons = try await TraktApi.shared.search(forPerson: text)
                }
            } catch {
                self.error = error
            }
            self.isLoading = false
        }
    }
}
