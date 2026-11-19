import Foundation

/// When each part of the notch moves as it changes state, in seconds. The shape morphs at once, so nothing here delays
/// a hover opening the notch or a click on play/pause; the content follows it in and leaves ahead of it.
public enum NotchMotion {
    /// The change of shape between states, on one smooth curve with no bounce.
    public static let morph: TimeInterval = 0.3
    /// Content waits this long before fading in, so the growing shape uncovers it rather than it showing up first.
    public static let contentDelay: TimeInterval = 0.1
    /// How long content takes to fade in once it starts.
    public static let contentIn: TimeInterval = 0.22
    /// How long content takes to fade out, well before the shape has closed over it.
    public static let contentOut: TimeInterval = 0.12

    /// How small the resting art starts, as a fraction of its size, before it grows into place.
    public static let artScale = 0.6
    /// The resting art starts to grow this long after the shape starts to move.
    public static let artDelay: TimeInterval = 0.06
    /// How long the resting art takes to grow into place.
    public static let artGrow: TimeInterval = 0.3

    /// The first play-state bar starts to rise this long after the shape starts to move, once the art is on its way.
    public static let barsDelay: TimeInterval = 0.16
    /// The gap between one bar starting to rise and the next.
    public static let barStagger: TimeInterval = 0.05
    /// How long each bar takes to rise.
    public static let barRise: TimeInterval = 0.26
    /// How long the bars take to drop as the content leaves, all together.
    public static let barDrop: TimeInterval = 0.14

    /// How long after the shape starts to move the bar at `index`, counting from the left, starts to rise. With Reduce
    /// Motion they all show at once.
    public static func barDelay(_ index: Int, reduceMotion: Bool = false) -> TimeInterval {
        reduceMotion ? 0 : barsDelay + Double(index) * barStagger
    }

    /// How long after the shape starts to move the last of `count` bars has risen, and they all move.
    public static func barsRisen(count: Int, reduceMotion: Bool = false) -> TimeInterval {
        guard count > 0 else { return 0 }
        return reduceMotion ? 0 : barDelay(count - 1) + barRise
    }

    /// How long the old art takes to fade and shrink when the track changes under the open card.
    public static let trackArtOut: TimeInterval = 0.18
    /// How long the new art takes to fade in once it arrives; the spring that settles it runs a little longer.
    public static let trackArtIn: TimeInterval = 0.25
    /// How small the old art ends and the new art starts, as a fraction of its size.
    public static let trackArtScale = 0.9
    /// The spring that settles the new art: its duration, and how much it overshoots (0 is none). The overshoot is a few
    /// percent of a 56 pt tile, which the card's padding has room for.
    public static let trackArtSpringDuration: TimeInterval = 0.45
    public static let trackArtSpringBounce = 0.3
    /// How long the tile takes to glide to a new width, so the text beside it slides rather than jumps.
    public static let trackTileWidth: TimeInterval = 0.3

    /// The title starts to slide in this long after the track changes; the artist and album follow, one `trackLineStagger` apart.
    public static let trackLineDelay: TimeInterval = 0.05
    /// The gap between one line of text starting to slide in and the next.
    public static let trackLineStagger: TimeInterval = 0.05
    /// How long each line takes to slide in.
    public static let trackLineIn: TimeInterval = 0.28
    /// How long the old line takes to fade out, all lines together.
    public static let trackLineOut: TimeInterval = 0.12
    /// How far below its place a line starts, in points.
    public static let trackLineOffset = 8.0

    /// How long after the track changes the line at `index` (0 the title, 1 the artist, 2 the album) starts to slide in.
    /// With Reduce Motion they all fade in at once.
    public static func trackLineStart(_ index: Int, reduceMotion: Bool = false) -> TimeInterval {
        reduceMotion ? 0 : trackLineDelay + Double(index) * trackLineStagger
    }
    /// How small a playback button gets, as a fraction of its size, while it's held down.
    public static let pressScale = 0.88
    /// How far, in points, previous and next slide toward their skip direction while held down.
    public static let pressNudge: Double = 3
    /// How long a button takes to shrink once pressed. It's quick so the press reads as the click itself.
    public static let pressDown: TimeInterval = 0.08
    /// The spring a pressed button returns on, as its response in seconds and its damping. Under 1 so it overshoots a little.
    public static let pressReleaseResponse: TimeInterval = 0.32
    public static let pressReleaseDamping = 0.55
    /// How long the play and pause symbols take to swap.
    public static let symbolSwap: TimeInterval = 0.3
    /// How long the volume bar takes to ease to a volume set by the scroll wheel, a key or mute. A drag skips it.
    public static let volumeEase: TimeInterval = 0.18
    /// How long the speaker and output symbols take to swap, and the volume bar and the "macOS kept the sound" note to
    /// cross-fade.
    public static let statusSymbolSwap: TimeInterval = 0.2
}

// MARK: - Small delights: the heart, shuffle and repeat, and the empty and play-again cards

extension NotchMotion {
    /// How big the heart swells when it's liked, as a multiple of its size. Small enough to stay inside the title's row.
    public static let heartPopScale = 1.3
    /// How long the heart takes to swell when it's liked.
    public static let heartPopUp: TimeInterval = 0.12
    /// How long the heart takes to spring back to its size after swelling.
    public static let heartSettle: TimeInterval = 0.35
    /// How small the heart starts, as a fraction of its size, when it first shows beside the title.
    public static let heartAppearScale = 0.5
    /// How long the heart takes to scale and fade in.
    public static let heartAppear: TimeInterval = 0.25

    /// How small the on-dot under shuffle and repeat starts, as a fraction of its size, when a mode turns on.
    public static let dotScale = 0.2
    /// How long the on-dot takes to scale in or out.
    public static let dotChange: TimeInterval = 0.25

    /// How far below its place, in points, the empty note and the play-again card start before they rise.
    public static let riseDistance = 6.0
    /// How long the note and the card parts take to rise into place.
    public static let rise: TimeInterval = 0.3
    /// The gap between one part of the play-again card (art, then text, then play icon) starting to rise and the next.
    public static let recallStagger: TimeInterval = 0.05
    /// How big the play icon grows on the play-again card while the pointer is on it, as a multiple of its size.
    public static let playHoverScale = 1.2
    /// How long the play icon takes to change size as the pointer comes or goes.
    public static let playHover: TimeInterval = 0.18

    /// How long after the shape starts to move the part of the play-again card at `index` (0 art, 1 text, 2 play icon)
    /// starts to rise: after the content has started to fade in, then one stagger apart. With Reduce Motion they all
    /// fade together.
    public static func recallDelay(_ index: Int, reduceMotion: Bool = false) -> TimeInterval {
        reduceMotion ? contentDelay : contentDelay + Double(index) * recallStagger
    }
}
