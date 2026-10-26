import Foundation

/// When each part of the notch moves as it changes state, in seconds. The shape morphs at once, so nothing here delays
/// a hover opening the notch or a click on play/pause; the content follows it in and leaves ahead of it.
public enum NotchMotion {
    /// The change of shape between states, on one smooth curve with no bounce.
    public static let morph: TimeInterval = 0.25
    /// Content waits this long before fading in, so the growing shape uncovers it rather than it showing up first.
    public static let contentDelay: TimeInterval = 0.09
    /// How long content takes to fade in once it starts.
    public static let contentIn: TimeInterval = 0.2
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
}
