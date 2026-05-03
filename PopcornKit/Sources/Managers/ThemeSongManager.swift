

import Foundation
import AVFoundation
import SwiftyJSON

/// Class for managing TV Show and Movie Theme songs.
public class ThemeSongManager: @unchecked Sendable {
    
    /// Global player ref.
    private var player: AVAudioPlayer?
    
    /// Global download task ref.
    private var task: URLSessionTask?
    
    /// Creates new instance of ThemeSongManager class
    public static let shared: ThemeSongManager = ThemeSongManager()
    
    /**
     Starts playing TV Show theme music.
     
     - Parameter id: TVDB id of the show.
     */
    public func playShowTheme(_ id: Int) {
        playTheme("http://tvthemes.plexapp.com/\(id).mp3")
    }
    
    /**
     Starts playing Movie theme music.
     
     - Parameter name: The name of the movie.
     */
    public func playMovieTheme(_ name: String) {
        Task { @MainActor in
            let client = HttpClient(config: .init(serverURL: "https://itunes.apple.com/search"))
            let params: [String: Any] = ["term": "\(name) soundtrack", "media": "music", "attribute": "albumTerm", "limit": 1]
            let data = try await client.request(.get, path: "", parameters: params).responseData()
            let responseDict = JSON(data)
            if let url = responseDict["results"].arrayValue.first?["previewUrl"].string {
                self.playTheme(url)
            }
        }
    }
    
    /**
     Starts playing theme music from URL.
     
     - Parameter url: Valid url pointing to a track.
     */
    private func playTheme(_ url: String) {
//        if let player = player, player.isPlaying { player.stop() }
//        
//        self.task = URLSession.shared.dataTask(with: URL(string: url)!, completionHandler: { (data, response, error) in
//            do {
//                if let data = data {
//                    #if os(iOS) || os(tvOS)
//                    try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: AVAudioSession.Mode.default)
//                    #endif
//
//                    let adjustedVolume = Session.themeSongVolume * 0.25
//                    if adjustedVolume > 0 {
//                        let player = try AVAudioPlayer(data: data)
//                        player.volume = 0
//                        player.numberOfLoops = NSNotFound
//                        player.delegate = self
//                        player.prepareToPlay()
//                        player.play()
//                        
//                        player.setVolume(adjustedVolume, fadeDuration: 3.0)
//                        
//                        self.player = player
//                    }
//                }
//            } catch let error {
//                print(error)
//            }
//        })
//        task?.resume()
    }
    
    /// Stops playing theme music, if previously playing.
    public func stopTheme() {
        let delay = 1.0
        player?.setVolume(0, fadeDuration: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.player?.stop()
            self.task?.cancel()
            self.task = nil
        }
    }
}
