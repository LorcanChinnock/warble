import Foundation

/// The end of the playback bar's filled part. At rest it is the bar's own rounded tip; with the pointer over the bar,
/// or while it's dragged, it grows into a round knob, joined to the bar by a curve on each side so the bar and knob
/// read as one shape rather than a circle sitting on a line.
///
/// Positions are in points along a bar `width` wide, with y measured down from the bar's centre line. Only the top
/// curve is given; the bottom one is the same with y negated.
public struct ScrubberHandle: Equatable, Sendable {
    /// The bar's thickness.
    public static let barHeight: CGFloat = 4
    /// The knob's size once grown.
    public static let knobDiameter: CGFloat = 9
    /// The radius of the curve joining the bar's edge to the knob.
    public static let filletRadius: CGFloat = 12
    /// How long the knob takes to grow or shrink as the pointer comes and goes.
    public static let growDuration: TimeInterval = 0.15

    /// The x of the knob's centre, kept far enough in that the knob never hangs over either end of the bar.
    public let centre: CGFloat
    /// The knob's radius: half the bar's height at rest, so the knob is just the bar's rounded tip, and half
    /// `knobDiameter` once grown.
    public let radius: CGFloat
    /// The curve from the bar's top edge onto the knob, or `nil` when there is nothing to join (at rest) or no room
    /// for it (a knob right at the start of the bar).
    public let fillet: Fillet?

    /// A cubic curve along the bar's top edge and onto the knob, tangent to both.
    public struct Fillet: Equatable, Sendable {
        /// On the bar's top edge, where the curve leaves it.
        public let start: CGPoint
        public let control1: CGPoint
        public let control2: CGPoint
        /// On the knob, where the curve meets it.
        public let end: CGPoint
    }

    /// How far along a bar `width` wide the point `x` is, from 0 at its start to 1 at its end. A pointer dragged
    /// past either end counts as that end.
    public static func fraction(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1))
    }

    /// The time in a track `duration` long at the point `x` along a bar `width` wide, which a click there seeks to,
    /// or `nil` for a track with no known length, such as a live stream.
    public static func time(atX x: CGFloat, width: CGFloat, duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration > 0 else { return nil }
        return fraction(atX: x, width: width) * duration
    }

    /// The label over the bar at the point `x` along it: the time there, written as the elapsed time is ("3:07"),
    /// or `nil` for a track with no known length.
    public static func timeLabel(atX x: CGFloat, width: CGFloat, duration: TimeInterval?) -> String? {
        time(atX: x, width: width, duration: duration).map(PlaybackState.positionLabel)
    }

    /// - Parameters:
    ///   - fraction: how far through the track the playback is, 0 to 1.
    ///   - width: the bar's length.
    ///   - grown: 0 at rest, 1 with the pointer over the bar, and in between while it animates.
    public init(fraction: Double, width: CGFloat, grown: Double) {
        let half = Self.barHeight / 2
        let grown = CGFloat(min(max(grown, 0), 1))
        let radius = half + (Self.knobDiameter / 2 - half) * grown
        let fraction = CGFloat(min(max(fraction, 0), 1))
        let centre = width > 2 * radius ? min(max(width * fraction, radius), width - radius) : width / 2
        self.radius = radius
        self.centre = centre
        fillet = Self.fillet(centre: centre, radius: radius)
    }

    private static func fillet(centre: CGFloat, radius: CGFloat) -> Fillet? {
        let half = barHeight / 2
        let rho = filletRadius
        // The fillet's circle touches the bar's top edge and the outside of the knob.
        let reach = ((radius + rho) * (radius + rho) - (half + rho) * (half + rho)).squareRoot()
        let start = centre - reach
        // Too small a knob has no corner to round, and one at the very start would curve past the bar's end.
        guard reach > 0.01, start >= half else { return nil }
        let circle = CGPoint(x: start, y: -(half + rho))
        // From straight below the fillet's centre (the bar's edge) round to the line towards the knob's centre.
        let from = CGFloat.pi / 2
        let to = atan2(half + rho, reach)
        let k = 4 / 3 * tan((to - from) / 4) * rho
        let point = { (angle: CGFloat) in CGPoint(x: circle.x + rho * cos(angle), y: circle.y + rho * sin(angle)) }
        let p0 = point(from), p3 = point(to)
        return Fillet(
            start: p0,
            control1: CGPoint(x: p0.x - k * sin(from), y: p0.y + k * cos(from)),
            control2: CGPoint(x: p3.x + k * sin(to), y: p3.y - k * cos(to)),
            end: p3
        )
    }
}
