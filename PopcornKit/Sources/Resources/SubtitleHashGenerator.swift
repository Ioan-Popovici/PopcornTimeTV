//
//  This Swift 3 version is based on Swift 2 version by eduo:
//  https://gist.github.com/eduo/7188bb0029f3bcbf03d4
//
//  Created by Niklas Berglund on 2017-01-01.
//
import Foundation

public class OpenSubtitlesHash: NSObject {
    private static let chunkSize: Int = 65536
    
    public struct VideoHash: Equatable, Sendable {
        var fileHash: String
        var fileSize: UInt64
    }
    
    public class func hashFor(_ url: URL) -> VideoHash {
        return self.hashFor(url.path)
    }

    public class func hashFor(_ path: String) -> VideoHash {
        let emptyHash = VideoHash(fileHash: "", fileSize: 0)

        // Missing file (e.g. early-server-start handed us the path before
        // libtorrent created the on-disk allocation) → empty hash, callers
        // fall through to imdb/episode-based subtitle search.
        guard let fileHandler = FileHandle(forReadingAtPath: path) else {
            return emptyHash
        }
        defer { try? fileHandler.close() }

        do {
            let fileSize = try fileHandler.seekToEnd()
            // Need both head and tail chunks for a meaningful hash.
            guard fileSize >= UInt64(chunkSize) * 2 else {
                return emptyHash
            }

            try fileHandler.seek(toOffset: 0)
            guard let beginData = try fileHandler.read(upToCount: chunkSize),
                  beginData.count == chunkSize else {
                return emptyHash
            }

            try fileHandler.seek(toOffset: fileSize - UInt64(chunkSize))
            guard let endData = try fileHandler.read(upToCount: chunkSize),
                  endData.count == chunkSize else {
                return emptyHash
            }

            var hash: UInt64 = fileSize
            beginData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for word in raw.bindMemory(to: UInt64.self) {
                    hash = hash &+ word
                }
            }
            endData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for word in raw.bindMemory(to: UInt64.self) {
                    hash = hash &+ word
                }
            }

            return VideoHash(
                fileHash: String(format: "%016qx", hash),
                fileSize: fileSize
            )
        } catch {
            return emptyHash
        }
    }
}

// Usage example:
// let videoUrl = Bundle.main.url(forResource: "dummy5", withExtension: "rar")
// let videoHash = OpenSubtitlesHash.hashFor(videoUrl!)
// debugPrint("File hash: \(videoHash.fileHash)\nFile size: \(videoHash.fileSize)")
