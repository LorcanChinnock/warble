import Foundation

/// How a title that doesn't fit scrolls, in a virtual notch or on the expanded card: a slow loop while the song plays,
/// otherwise still with its end faded or cut.
public enum TitleScroll {
    /// How fast the text moves, in points a second: slow enough to read.
    public static let speed = 18.0
    /// The empty space between the end of the title and its start coming round again.
    public static let gap = 36.0

    /// How long the expanded card holds a cut-off line still before it starts moving, so it can be read first.
    public static let startDelay: TimeInterval = 1.5

    /// Whether `line` scrolls: it is cut, the song plays, and Reduce Motion is off.
    public static func scrolls(_ line: TrackTitle.Line, isPlaying: Bool, reduceMotion: Bool) -> Bool {
        line.isCut && isPlaying && !reduceMotion
    }

    /// Whether a line of `textWidth` points scrolls in `width` points: it is cut, the song plays, and Reduce Motion is off.
    public static func scrolls(textWidth: Double, width: Double, isPlaying: Bool, reduceMotion: Bool) -> Bool {
        textWidth > width && isPlaying && !reduceMotion
    }

    /// How far the text moves before the loop starts over: its own width and the gap, so the title comes round as it left.
    public static func distance(textWidth: Double) -> Double {
        textWidth + gap
    }

    /// How long one loop takes, in seconds.
    public static func duration(textWidth: Double) -> TimeInterval {
        distance(textWidth: textWidth) / speed
    }
}
