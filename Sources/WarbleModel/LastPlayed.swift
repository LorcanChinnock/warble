import Foundation

/// The last track Warble saw, which the idle card shows and Warble keeps across launches.
public struct LastPlayed: Codable, Equatable, Sendable {
    /// The app that played it, such as `com.apple.Music`. For a tab, the browser.
    public var bundleIdentifier: String
    /// The app's name as it was when the track played, for when the app isn't running or has gone.
    public var appName: String?
    public var title: String
    public var artist: String?
    /// A small copy of the art, encoded, so the saved track stays a few kilobytes.
    public var artwork: Data?

    public init(bundleIdentifier: String, appName: String? = nil, title: String, artist: String? = nil, artwork: Data? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.artist = artist
        self.artwork = artwork
    }

    /// Whether `state` is worth remembering in place of `previous`, the state last remembered: a new track, or the art
    /// arriving or changing. A pause, a seek or a change of speed isn't, so those never write to disk.
    public static func changes(from previous: PlaybackState?, to state: PlaybackState) -> Bool {
        guard let previous else { return true }
        return previous.bundleIdentifier != state.bundleIdentifier
            || previous.title != state.title
            || previous.artist != state.artist
            || previous.artwork != state.artwork
    }
}
