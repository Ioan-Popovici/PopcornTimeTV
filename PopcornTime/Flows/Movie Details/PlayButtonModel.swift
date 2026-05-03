//
//  PlayButtonModel.swift
//  PlayButtonModel
//
//  Created by Alexandru Tudose on 10.08.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import Foundation
import PopcornKit

@MainActor
class PlayButtonModel: ObservableObject {
    var media: Media
    var torrent: Torrent?
    
    init(media: Media) {
        self.media = media
    }
}
