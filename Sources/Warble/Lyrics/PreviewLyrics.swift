import Foundation
import WarbleCore

/// Lyrics for `-notchPreviewState resting` with lyrics on: a line every four seconds of the preview track, from a hymn
/// out of copyright, so the preview shows the strip without asking LRCLIB anything.
struct PreviewLyrics: LyricsProvider {
    /// "Amazing Grace", John Newton, 1779.
    private static let verse = [
        "Amazing grace, how sweet the sound",
        "That saved a wretch like me",
        "I once was lost, but now am found",
        "Was blind, but now I see",
        "",
    ]

    func lyrics(for query: LyricsQuery) async -> String? {
        stride(from: 0, to: query.duration ?? 240, by: 4).enumerated().map { index, seconds in
            let line = Self.verse[index % Self.verse.count]
            return "[\(String(format: "%02d:%02d.00", seconds / 60, seconds % 60))] \(line)"
        }
        .joined(separator: "\n")
    }
}
