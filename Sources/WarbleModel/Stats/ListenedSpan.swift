import Foundation

/// A stretch of one track playing without a break, which is all the listening stats keep: when it began, how long it
/// lasted and which track it was. Pausing, skipping and quitting each end one.
public struct ListenedSpan: Codable, Equatable, Sendable {
    /// Shorter than this, a span is a skip through tracks rather than listening, and isn't kept.
    public static let shortest: TimeInterval = 1

    public var start: Date
    public var seconds: TimeInterval
    public var title: String
    public var artist: String?

    public init(start: Date, seconds: TimeInterval, title: String, artist: String? = nil) {
        self.start = start
        self.seconds = seconds
        self.title = title
        self.artist = artist
    }
}
