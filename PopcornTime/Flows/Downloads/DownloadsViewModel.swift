//
//  DownloadsViewModel.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 08.07.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import PopcornTorrent
import PopcornKit
import MediaPlayer

@MainActor
class DownloadsViewModel: NSObject, ObservableObject {
    @Published var error: Error?
    nonisolated(unsafe) var downloadManager = PTTorrentDownloadManager.shared()
    
    @Published var completedMovies: [PTTorrentDownload] = []
    @Published var downloading: [PTTorrentDownload] = []
    @Published var completedEpisodes: [PTTorrentDownload] = []
    
    override init() {
        super.init()
        downloadManager.add(self)
    }
    
    deinit {
        downloadManager.remove(self)
    }
    
    func reload() {
        completedMovies = filter(downloads: downloadManager.completedDownloads, through: .movie)
        completedEpisodes = filter(downloads: downloadManager.completedDownloads, through: .episode)
        downloading = downloadManager.activeDownloads
    }
    
    var isEmpty: Bool {
        return completedMovies.isEmpty && completedEpisodes.isEmpty && downloading.isEmpty
    }
    
    private func filter(downloads: [PTTorrentDownload], through predicate: MPMediaType) -> [PTTorrentDownload] {
        return downloads.filter { download in
            guard let rawValue = download.mediaMetadata[MPMediaItemPropertyMediaType] as? NSNumber else { return false }
            let type = MPMediaType(rawValue: rawValue.uintValue)
            return type == predicate
        }.sorted { (first, second) in
            guard
                let firstTitle = first.mediaMetadata[MPMediaItemPropertyTitle] as? String,
                let secondTitle = second.mediaMetadata[MPMediaItemPropertyTitle] as? String
                else {
                    return false
            }
            return firstTitle > secondTitle
        }
    }
    
}

extension DownloadsViewModel: @preconcurrency PTTorrentDownloadManagerListener {
    nonisolated func downloadStatusDidChange(_ downloadStatus: PTTorrentDownloadStatus, for download: PTTorrentDownload) {
        Task { @MainActor [weak self] in
            self?.reload()
        }
    }

    nonisolated func downloadDidFail(_ download: PTTorrentDownload, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.error = error
            self?.reload()
        }
    }
}
