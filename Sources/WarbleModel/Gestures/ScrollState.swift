import Foundation

/// What a scroll over a notch does: it changes the volume, or with swipe to skip on, a sideways trackpad swipe skips.
public struct ScrollState: Feature {
    /// Whether a sideways swipe over a notch skips, which Settings turns on.
    public internal(set) var swipeToSkip: Bool
    /// The trackpad gesture under way.
    public internal(set) var swipe = Swipe()

    public init(swipeToSkip: Bool = false) {
        self.swipeToSkip = swipeToSkip
    }

    var deadline: Date? { nil }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .scrolled(let delta, let across, let phase, let precise, let inverted, let volume, let isMuted):
            // Scrolling over the notch changes the volume. With swipe to skip on, a trackpad gesture goes one way only, so
            // a sideways swipe skips once and leaves the volume alone. A wheel has no gesture and only scrolls.
            guard swipeToSkip, precise, let phase else {
                return Self.volume(delta, precise: precise, inverted: inverted, volume: volume, isMuted: isMuted)
            }
            switch swipe.handle(across: across, down: delta, phase: phase, inverted: inverted) {
            case .volume(let delta):
                return Self.volume(delta, precise: precise, inverted: inverted, volume: volume, isMuted: isMuted)
            case .skip(let command):
                // Skipping needs something to skip; with nothing playing the swipe does nothing.
                if shared.showsPlayback, shared.playback != nil {
                    return [.send(command), .haptic]
                }
            case .nothing:
                break
            }
        case .swipeToSkipChanged(let on):
            swipeToSkip = on
            swipe = Swipe()
        default:
            break
        }
        return []
    }

    /// The volume a scroll of `delta` sets, with a light tick on a Force Touch trackpad at each tenth.
    private static func volume(_ delta: Double, precise: Bool, inverted: Bool, volume: Double?, isMuted: Bool) -> [AppEffect] {
        guard let volume, delta != 0 else { return [] }
        let from = isMuted ? 0 : volume
        let to = VolumeScroll.volume(after: delta, from: from, precise: precise, inverted: inverted)
        guard to != from else { return [] }
        return VolumeScroll.crossesTick(from: from, to: to) ? [.setVolume(to), .haptic] : [.setVolume(to)]
    }
}
