import Foundation

/// What a track-change toast shows: the new track's title and artist.
public struct TrackToast: Hashable, Sendable {
    public var title: String
    public var artist: String?

    /// How long a track-change toast shows.
    public static let duration: TimeInterval = 2

    public init(title: String, artist: String? = nil) {
        self.title = title
        self.artist = artist
    }

    /// The toast to post when `state` follows `previous`, or `nil` unless it's a new track: another title, artist or app.
    /// The first report, from nothing, isn't a change, since the notch is only just showing the track; nor is a pause, a
    /// seek or the art arriving late.
    public static func notice(from previous: PlaybackState?, to state: PlaybackState) -> Notice<TrackToast>? {
        guard let previous,
              previous.bundleIdentifier != state.bundleIdentifier || previous.title != state.title || previous.artist != state.artist
        else { return nil }
        return Notice(kind: .trackChanged, content: TrackToast(title: state.title, artist: state.artist), duration: duration)
    }
}
