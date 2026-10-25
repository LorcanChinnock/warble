import Foundation

/// The last seven days of listening: the total, and the artists and tracks heard most.
public struct WeeklySummary: Equatable, Sendable {
    public struct Artist: Hashable, Sendable {
        public var name: String
        public var seconds: TimeInterval
    }

    public struct Track: Hashable, Sendable {
        public var title: String
        public var artist: String?
        public var seconds: TimeInterval
    }

    /// How far back the summary looks.
    public static let window: TimeInterval = 7 * 24 * 3600
    /// How far back spans are kept at all, so the file doesn't grow for ever.
    public static let retention: TimeInterval = 30 * 24 * 3600
    /// How many artists and tracks it lists.
    public static let listed = 5

    public var totalSeconds: TimeInterval
    public var topArtists: [Artist]
    public var topTracks: [Track]

    public var isEmpty: Bool { totalSeconds == 0 }
    /// Whether any span was kept at all, even one older than the week, so Clear stays available while there's history to delete.
    public var holdsHistory: Bool

    public static let empty = WeeklySummary(totalSeconds: 0, topArtists: [], topTracks: [], holdsHistory: false)

    /// The summary of the spans that began in the seven days up to `now`. Equal times are ordered by name, so the same
    /// spans always give the same lists.
    public init(_ spans: [ListenedSpan], at now: Date) {
        holdsHistory = !spans.isEmpty
        let since = now.addingTimeInterval(-Self.window)
        let recent = spans.filter { $0.start >= since && $0.start <= now }
        totalSeconds = recent.reduce(0) { $0 + $1.seconds }
        var artists: [String: TimeInterval] = [:]
        struct Key: Hashable { var title: String; var artist: String? }
        var tracks: [Key: TimeInterval] = [:]
        for span in recent {
            if let artist = span.artist, !artist.isEmpty {
                artists[artist, default: 0] += span.seconds
            }
            tracks[Key(title: span.title, artist: span.artist), default: 0] += span.seconds
        }
        topArtists = artists
            .map { Artist(name: $0.key, seconds: $0.value) }
            .sorted { ($1.seconds, $0.name) < ($0.seconds, $1.name) }
            .prefix(Self.listed).map { $0 }
        topTracks = tracks
            .map { Track(title: $0.key.title, artist: $0.key.artist, seconds: $0.value) }
            .sorted { ($1.seconds, $0.title, $0.artist ?? "") < ($0.seconds, $1.title, $1.artist ?? "") }
            .prefix(Self.listed).map { $0 }
    }

    private init(totalSeconds: TimeInterval, topArtists: [Artist], topTracks: [Track], holdsHistory: Bool) {
        self.holdsHistory = holdsHistory
        self.totalSeconds = totalSeconds
        self.topArtists = topArtists
        self.topTracks = topTracks
    }
}
