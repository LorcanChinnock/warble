import Foundation

/// The volume a scroll has set, so the next event of the same scroll carries on from it rather than from a device that may
/// still report the old one.
public struct HeldVolume: Sendable {
    /// How long after a scroll event the volume it set still counts.
    static let window = 0.5

    private var held: (value: Double, at: TimeInterval)?

    public init() {}

    /// The volume a scroll event at `time` starts from: the one the last event set if that was within the window,
    /// otherwise what `device` reads. It also works out what this event sets, for the next.
    public mutating func start(delta: Double, device: () -> Double?, isMuted: Bool, precise: Bool, inverted: Bool, at time: TimeInterval) -> Double? {
        let current = held.flatMap { time - $0.at < Self.window ? $0.value : nil } ?? device()
        held = current.map { (VolumeScroll.volume(after: delta, from: isMuted ? 0 : $0, precise: precise, inverted: inverted), time) }
        return current
    }
}

/// How scrolling over the notch changes the output volume, from 0 to 1.
public enum VolumeScroll {
    /// A mouse wheel's click moves the volume as far as a volume key does: a sixteenth.
    public static let wheelStep = 1.0 / 16
    /// A trackpad moves it by this much per point scrolled, so a long swipe goes from silent to full.
    public static let pointStep = 1.0 / 400

    /// The volume after a scroll of `delta`, as `NSEvent.scrollingDeltaY` reports it. `precise` is a trackpad or Magic
    /// Mouse, which reports points rather than wheel clicks. `inverted` is natural scrolling, which flips the delta, so
    /// moving fingers up raises the volume either way, as turning a wheel up does.
    public static func volume(after delta: Double, from volume: Double, precise: Bool, inverted: Bool) -> Double {
        let up = inverted ? -delta : delta
        return min(max(volume + up * (precise ? pointStep : wheelStep), 0), 1)
    }

    /// The volume a scroll of `delta` sets, with a light tick on a Force Touch trackpad at each tenth.
    static func effects(_ delta: Double, precise: Bool, inverted: Bool, volume: Double?, isMuted: Bool) -> [AppEffect] {
        guard let volume, delta != 0 else { return [] }
        let from = isMuted ? 0 : volume
        let to = Self.volume(after: delta, from: from, precise: precise, inverted: inverted)
        guard to != from else { return [] }
        return crossesTick(from: from, to: to) ? [.setVolume(to), .haptic] : [.setVolume(to)]
    }

    /// Whether going from `old` to `new` passes a tenth, such as 30%, for a haptic tick.
    public static func crossesTick(from old: Double, to new: Double) -> Bool {
        // Rounded first, so 0.3 read back from Core Audio as 0.29999 still counts as 30%.
        let tenth = { (volume: Double) in ((volume * 1000).rounded() / 100).rounded(.down) }
        return tenth(old) != tenth(new)
    }
}
