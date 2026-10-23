import Foundation

/// The track-change toast's part of `AppState`: the settings that turn it on, and the queue of what shows.
public struct ToastState: Feature {
    public internal(set) var queue = ToastQueue<TrackToast>()
    /// Whether a track change posts a toast, which Settings turns on.
    public internal(set) var isOn: Bool
    /// Whether the toast also shows over a full-screen app, which Settings turns on.
    public internal(set) var inFullScreen: Bool

    public init(isOn: Bool = false, inFullScreen: Bool = false) {
        self.isOn = isOn
        self.inFullScreen = inFullScreen
    }

    var deadline: Date? { queue.deadline }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .trackToastChanged(let on):
            isOn = on
            if !on {
                dismiss(at: now)
            }
        case .toastsInFullScreenChanged(let on):
            inFullScreen = on
        case .tick:
            queue.advance(to: now)
        default:
            break
        }
        return []
    }

    /// Posts `notice`, unless the setting is off, nothing shows or a notch is open, whose card has the track already.
    mutating func announce(_ notice: Notice<TrackToast>?, shared: SharedState, isOpen: Bool, at now: Date) {
        if let notice, isOn, shared.showsPlayback, !isOpen {
            queue.post(notice, at: now)
        }
    }

    /// Ends the toast showing, if any, and shows the next.
    mutating func dismiss(at now: Date) {
        guard queue.current != nil else { return }
        queue.dismiss(at: now)
    }
}
