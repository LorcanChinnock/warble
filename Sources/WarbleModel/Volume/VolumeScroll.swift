import Foundation

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
