import Foundation

/// Turns the audio tap's bands into the heights of the play-state bars, with smoothing so they rise quickly and fall back
/// slowly, as a level meter does. Pure, so it's tested on Linux; the frames themselves never pass through `reduce`.
public struct SpectrumBars: Equatable, Sendable {
    /// Where each band starts and ends, in Hz: bass, low mids, upper mids and treble. One bar for each.
    public static let bandEdges: [Double] = [60, 250, 1000, 4000, 12000]
    public static var count: Int { bandEdges.count - 1 }

    /// A band at or below this many dB (relative to a full-scale tone) is a bar at rest, and one at or above `ceiling`
    /// is a bar at full height. Music sits well below full scale, so the ceiling is not 0.
    static let floor = -70.0
    static let ceiling = -20.0
    /// How far a bar moves toward its level in each frame: quickly up, slowly down.
    static let attack = 0.7
    static let release = 0.18

    /// Each bar's height from 0 to 1.
    public private(set) var heights = [Double](repeating: 0, count: SpectrumBars.count)

    public init() {}

    /// Moves the bars toward `bands`, each a band's magnitude where a full-scale tone is 1, and returns their heights. A
    /// frame with the wrong number of bands is treated as silence.
    @discardableResult
    public mutating func update(_ bands: [Float]) -> [Double] {
        for index in heights.indices {
            let target = bands.count == heights.count ? Self.level(Double(bands[index])) : 0
            let rate = target > heights[index] ? Self.attack : Self.release
            heights[index] += (target - heights[index]) * rate
        }
        return heights
    }

    /// The bars at rest, for when the tap stops.
    public mutating func reset() {
        heights = [Double](repeating: 0, count: heights.count)
    }

    /// A magnitude as a height from 0 to 1, on a decibel scale since that's how loudness is heard.
    static func level(_ magnitude: Double) -> Double {
        guard magnitude.isFinite, magnitude > 0 else { return 0 }
        let decibels = 20 * log10(magnitude)
        return min(max((decibels - floor) / (ceiling - floor), 0), 1)
    }
}
