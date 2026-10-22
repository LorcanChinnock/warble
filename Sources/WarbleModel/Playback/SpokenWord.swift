import Foundation

/// Podcasts and audiobooks, which the player's card moves through by seconds rather than by track, and which have no
/// lyrics. A source says so with its media type, and for one that doesn't, the app playing is one that plays only speech.
public enum SpokenWord {
    /// How far the back and forward buttons go.
    public static let back: TimeInterval = 15
    public static let forward: TimeInterval = 30
    /// Apps that play only speech: Podcasts, and Books for audiobooks.
    static let apps: Set<String> = ["com.apple.podcasts", "com.apple.iBooksX"]

    /// Whether `playback` is a podcast episode or an audiobook.
    public static func contains(_ playback: PlaybackState) -> Bool {
        switch playback.mediaType {
        case .podcast, .audiobook: true
        case .music, .other, nil: apps.contains(playback.bundleIdentifier)
        }
    }
}
