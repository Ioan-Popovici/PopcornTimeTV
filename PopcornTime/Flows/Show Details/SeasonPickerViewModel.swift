//
//  SeasonPickerViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 05.07.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornKit

@MainActor
class SeasonPickerViewModel: ObservableObject {
    struct Season: Hashable {
        var number: Int
        var image: String?
    }
    
    @Published var show: Show
    @Published var seasons: [Season] = []
    @Published var isLoading = false
    
    init(show: Show) {
        self.show = show
    }
    
    func load() {
        guard !isLoading else {
            return
        }
        
        isLoading = true
        Task { @MainActor in
            if show.tmdbId == nil, let tmdbId = try? await TraktApi.shared.getTMDBId(forImdbId: show.id) {
                self.show.tmdbId = tmdbId
            }
            
            self.seasons = show.seasonNumbers.compactMap{ .init(number: $0, image: nil) }
            isLoading = false
        }
    }
}
