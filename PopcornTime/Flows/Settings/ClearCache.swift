//
//  ClearCache.swift
//  PopcornTime
//
//  Created by Alexandru Tudose on 28.11.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI

struct ClearCache {
    var title: LocalizedStringKey = ""
    var message: LocalizedStringKey = ""

    @MainActor
    public mutating func emptyCache() {
        // Drop libtorrent's in-memory torrent_handles for any warm
        // streamers BEFORE deleting their on-disk save_path. Without
        // this, the next Play call dedups on the stale handle and
        // GCDWebServer aborts when it tries to read pieces whose file
        // has been unlinked. Cached pieces are gone anyway, so the
        // user's next Play has to redownload — which is the point.
        TorrentSessionWarmer.shared.releaseAll()

        // Only touch the torrent streaming cache — `NSTemporaryDirectory()`
        // on macOS is the shared user temp folder (`/var/folders/…/T/`)
        // which contains files owned by other apps and the system; the
        // previous version tried to wipe the whole directory and aborted
        // on the first item it didn't have permission to delete.
        // PTTorrentStreamer puts its data under `<temp>/Downloads/`, so
        // that's the only path we should be clearing.
        //
        // We skip computing folder size — recursively stat-walking a
        // multi-gigabyte torrent cache on the main thread before
        // deletion blocks the UI for several seconds and looks like a
        // hang. `removeItem` does the destructive work atomically per
        // entry without needing the size up front.
        let cacheRoot = (NSTemporaryDirectory() as NSString).appendingPathComponent("Downloads")
        let fm = FileManager.default

        guard fm.fileExists(atPath: cacheRoot) else {
            title = "Cache empty"
            message = "Nothing to clear yet — no streaming cache has been created."
            return
        }

        var deleted = 0
        var failures = 0

        if let entries = try? fm.contentsOfDirectory(atPath: cacheRoot) {
            for entry in entries {
                let entryPath = (cacheRoot as NSString).appendingPathComponent(entry)
                do {
                    try fm.removeItem(atPath: entryPath)
                    deleted += 1
                } catch {
                    // Best-effort: a single in-use file shouldn't abort
                    // the whole operation. Keep going through the rest.
                    failures += 1
                }
            }
        }

        if deleted == 0 && failures == 0 {
            title = "Cache empty"
            message = "Cache was already empty."
        } else if failures == 0 {
            title = "Success"
            message = "Cleared \(deleted) cached item\(deleted == 1 ? "" : "s")."
        } else {
            title = "Partial"
            message = "Cleared \(deleted) item\(deleted == 1 ? "" : "s"); \(failures) couldn't be removed (likely in use)."
        }
    }
}
