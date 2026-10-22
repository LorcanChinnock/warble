import Foundation

/// Decides which source the notch follows when more than one app reports playback. By default it's the one that
/// started playing most recently; while none plays, the one that played last. A pinned source wins whenever it's there,
/// and an ignored one is never followed.
///
/// It knows sources only by bundle identifier and takes reports of each one playing, pausing or going away, so it
/// doesn't depend on how they're found.
public struct SourcePriority: Equatable, Sendable {
    /// Video call apps, whose audio is a call rather than something to show.
    public static let defaultIgnored: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.FaceTime",
    ]

    /// The source the user chose to follow while it's there, or `nil` to follow the most recent.
    public var pinned: String?
    /// Apps Warble never shows.
    public var ignored: Set<String>

    private struct Source: Equatable, Sendable {
        var isPlaying: Bool
        /// When it last started playing, or when it was first seen if it hasn't played since.
        var started: Date
        /// When it last stopped playing, or when it was first seen if it hasn't played since.
        var stopped: Date
    }

    private var sources: [String: Source] = [:]

    public init(pinned: String? = nil, ignored: Set<String> = Self.defaultIgnored) {
        self.pinned = pinned
        self.ignored = ignored
    }

    /// `source` reports that it's playing or paused, at `date`.
    public mutating func update(_ source: String, isPlaying: Bool, at date: Date) {
        guard var known = sources[source] else {
            sources[source] = Source(isPlaying: isPlaying, started: date, stopped: date)
            return
        }
        if isPlaying, !known.isPlaying {
            known.started = date
        } else if !isPlaying, known.isPlaying {
            known.stopped = date
        }
        known.isPlaying = isPlaying
        sources[source] = known
    }

    /// `source` stopped reporting playback, such as when the app quit or the tab closed.
    public mutating func remove(_ source: String) {
        sources[source] = nil
    }

    /// The source the notch follows, or `nil` when there's none to show.
    public var followed: String? {
        ranked.first
    }

    /// Every source Warble may show, the followed one first: the pinned source, then those playing by when they started,
    /// newest first, then those paused by when they stopped, newest first.
    public var ranked: [String] {
        sources
            .filter { !ignored.contains($0.key) }
            .sorted { lhs, rhs in
                let (left, right) = (lhs.value, rhs.value)
                if (lhs.key == pinned) != (rhs.key == pinned) { return lhs.key == pinned }
                if left.isPlaying != right.isPlaying { return left.isPlaying }
                let (leftDate, rightDate) = left.isPlaying ? (left.started, right.started) : (left.stopped, right.stopped)
                // The bundle identifier breaks a tie, so the order never depends on the dictionary's.
                return leftDate != rightDate ? leftDate > rightDate : lhs.key < rhs.key
            }
            .map(\.key)
    }
}
