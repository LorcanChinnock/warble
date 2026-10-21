import Foundation

/// What a key does while the notch is open from the keyboard: Space plays or pauses, ← and → seek, ⇧← and ⇧→ change
/// track, ↑ and ↓ change the volume, and Esc closes. Any other key, or one of these with ⌘, ⌥ or ⌃, does nothing, so
/// it reaches the focused control or the system.
public enum NotchKey: Equatable, Sendable {
    case command(PlaybackCommand)
    /// Seconds to move the position by, back when negative.
    case seek(by: TimeInterval)
    /// How much to change the volume by, from 0 to 1, down when negative.
    case volume(by: Double)
    case close

    /// How far ← and → move the position.
    public static let seekStep: TimeInterval = 10
    /// How far ↑ and ↓ move the volume: a sixteenth, as far as a volume key does.
    public static let volumeStep = VolumeScroll.wheelStep

    /// The key with virtual key code `keyCode` and `modifiers`, in `KeyCombo`'s mask, or `nil` for one the notch leaves
    /// alone.
    public init?(keyCode: UInt32, modifiers: UInt32) {
        let shift = modifiers == KeyCombo.shift
        guard modifiers == 0 || shift else { return nil }
        switch (keyCode, shift) {
        case (49, false): self = .command(.togglePlayPause)
        case (123, false): self = .seek(by: -Self.seekStep)
        case (124, false): self = .seek(by: Self.seekStep)
        case (123, true): self = .command(.previousTrack)
        case (124, true): self = .command(.nextTrack)
        case (126, false): self = .volume(by: Self.volumeStep)
        case (125, false): self = .volume(by: -Self.volumeStep)
        case (53, false): self = .close
        default: return nil
        }
    }

    /// Where a seek of `delta` from `playback`'s position at `date` lands, kept within the track, or `nil` for a live
    /// stream, which has no end to seek within.
    public static func position(seeking delta: TimeInterval, in playback: PlaybackState, at date: Date) -> TimeInterval? {
        guard let duration = playback.duration, duration > 0 else { return nil }
        return min(max(playback.elapsed(at: date) + delta, 0), duration)
    }

    /// The volume after a change of `delta` from `volume`, kept from 0 to 1.
    public static func volume(changing volume: Double, by delta: Double) -> Double {
        min(max(volume + delta, 0), 1)
    }
}
