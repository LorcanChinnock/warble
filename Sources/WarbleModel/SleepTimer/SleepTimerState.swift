import Foundation

/// The sleep timer's part of `AppState`: whether Settings has it on and the timer running, if any. It lasts only while
/// something plays, so a pause by hand, Idle, a source that stopped reporting or turning the setting off ends it.
public struct SleepTimerState: Feature {
    /// Whether the player's card has a sleep timer button, which Settings turns on.
    public internal(set) var isOn: Bool
    public internal(set) var timer: SleepTimer?

    public init(isOn: Bool = false) {
        self.isOn = isOn
    }

    var deadline: Date? { timer?.deadline }

    /// Whether a timer can start now: Settings has it on and something is playing, not about to be hidden.
    func canSet(_ shared: SharedState) -> Bool {
        shared.hideAt == nil && keeps(shared)
    }

    /// Whether a running timer stays: Settings has it on and something is playing. It outlasts the gap a source leaves
    /// between tracks (`hideAt`), since the next track's report is what ends an End of track timer.
    private func keeps(_ shared: SharedState) -> Bool {
        isOn && shared.showsPlayback && shared.playback?.isPlaying == true
    }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .setSleepTimer(let choice?):
            // Replaces the one running. Only while something plays, since a timer with nothing playing has nothing to
            // pause, and End of track needs a track with a length.
            if canSet(shared), let playback = shared.playback {
                timer = SleepTimer(choice, playback: playback, at: now) ?? timer
            }
        case .setSleepTimer(nil):
            timer = nil
        case .sleepTimerSettingChanged(let on):
            isOn = on
        default:
            break
        }
        return []
    }

    /// Brings the timer up to date with what's playing, ends it when it can't last, and says whether it's due, which
    /// ends it too. The caller pauses.
    mutating func expire(_ shared: SharedState, at now: Date) -> SleepTimer.Status {
        guard var running = timer else { return .waiting }
        guard keeps(shared), let playback = shared.playback else {
            timer = nil
            return .waiting
        }
        guard running.follow(playback, at: now) == .due else {
            timer = running
            return .waiting
        }
        timer = nil
        return .due
    }
}
