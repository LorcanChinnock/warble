import Foundation
import WarbleModel

/// The track the first-run demo plays: nothing real, so it can be named in the user's language.
enum DemoTrack {
    static func playback(startedAt: Date) -> PlaybackState {
        PlaybackState(
            bundleIdentifier: "com.apple.Music",
            title: String(localized: "What's playing"),
            artist: String(localized: "Your music shows up here"),
            album: nil,
            duration: 240,
            elapsed: 60,
            elapsedTimestamp: startedAt,
            rate: 1,
            shuffle: .off,
            repeatMode: .off
        )
    }
}
