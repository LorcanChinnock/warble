import Foundation

/// The live waveform: whether Settings has it on, and whether the audio tap runs. The tap runs only while it can be seen:
/// the setting is on and a notch is drawing its bars at rest for something that's playing. It never runs while paused,
/// Idle, hidden or with a card open, and macOS never asks to record while the setting is off.
struct WaveformState: Feature {
    var isOn: Bool
    /// What the tap was last asked to do, so it's asked once each time that changes.
    var captures = false

    init(isOn: Bool = false) {
        self.isOn = isOn
    }

    var deadline: Date? { nil }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .waveformChanged(let on):
            isOn = on
        case .audioCaptureDenied:
            // macOS said no, or the tap wouldn't start. Settings says why, and turning the setting on tries again.
            isOn = false
            return [.turnOffWaveform]
        default:
            break
        }
        return []
    }

    /// Asks the tap to start or stop when `drawsBars` changes the answer.
    mutating func follow(drawsBars: Bool) -> [AppEffect] {
        let captures = isOn && drawsBars
        guard captures != self.captures else { return [] }
        self.captures = captures
        return [.captureAudio(captures)]
    }
}
