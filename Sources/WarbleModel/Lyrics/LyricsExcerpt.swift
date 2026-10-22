import Foundation

/// The lines the lyrics card shows: one near the top, with one before it and three after, leaving out gaps such as an
/// instrumental break. The middle one is the line being sung, or before the first line and in a gap, the next to be.
public struct LyricsExcerpt: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        /// The line's place in `Lyrics.lines`, so a line keeps its row as the card moves on.
        public let id: Int
        public let text: String
        /// Whether it's the line being sung.
        public let isCurrent: Bool
    }

    /// How many lines show before the middle one, and after it.
    public static let before = 1
    public static let after = 3

    /// In the order they're sung.
    public let rows: [Row]
    /// How many rows are missing before the first, near the start of the song, so the middle line keeps its place.
    public let missingBefore: Int

    /// The lines around `position`, or `nil` when the lyrics have no words at all.
    init?(_ lyrics: Lyrics, at position: TimeInterval) {
        let sung = lyrics.sung
        guard !sung.isEmpty else { return nil }
        let started = lyrics.index(at: position)
        // The first line with words that starts after `started`, found by halving.
        var (low, high) = (0, sung.count)
        while low < high {
            let middle = (low + high) / 2
            if sung[middle] <= (started ?? -1) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let current = low > 0 && sung[low - 1] == started ? low - 1 : nil
        // Where the middle line is in `sung`, or `nil` after the last line with words has been sung and a gap follows.
        let middle = current ?? (low < sung.count ? low : nil)
        let end = middle ?? sung.count
        let first = max(end - Self.before, 0)
        let last = middle.map { min($0 + Self.after, sung.count - 1) } ?? sung.count - 1
        rows = sung[first...last].map { Row(id: $0, text: lyrics.lines[$0].text, isCurrent: current.map { sung[$0] } == $0) }
        missingBefore = Self.before - (end - first)
    }
}
