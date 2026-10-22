import Foundation

/// What Warble asks a lyrics service for: the track's artist, title, album and length, as the source reported them.
public struct LyricsQuery: Hashable, Sendable {
    public var artist: String
    public var title: String
    /// `nil` when the source reports no album.
    public var album: String?
    /// The length in whole seconds, or `nil` for a live stream or a source that doesn't say.
    public var duration: Int?

    public init(artist: String, title: String, album: String? = nil, duration: Int? = nil) {
        self.artist = artist
        self.title = title
        self.album = album
        self.duration = duration
    }

    /// The query for what `state` plays, or `nil` without an artist or a title, since a lyrics service can't find a
    /// song without both. Each field is trimmed, and an empty album counts as none.
    public init?(_ state: PlaybackState) {
        let artist = Self.trimmed(state.artist)
        let title = Self.trimmed(state.title)
        guard let artist, let title else { return nil }
        self.init(artist: artist, title: title, album: Self.trimmed(state.album), duration: Self.seconds(state.duration))
    }

    /// The same for every report of one track, whatever its position or art, and different when any field differs.
    /// Each field is prefixed with its length in UTF-8 bytes, so no title can run into the album beside it.
    public var cacheKey: String {
        [artist, title, album ?? "", duration.map(String.init) ?? ""]
            .map { "\($0.utf8.count):\($0)" }
            .joined()
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// `duration` rounded to whole seconds, or `nil` when it isn't a length a song could have: none, zero, or more than
    /// a day, which also keeps the conversion to `Int` from trapping.
    private static func seconds(_ duration: TimeInterval?) -> Int? {
        guard let duration, duration >= 0.5, duration <= 86_400 else { return nil }
        return Int(duration.rounded())
    }
}
