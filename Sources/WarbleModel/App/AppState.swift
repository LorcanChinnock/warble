import Foundation

/// Everything the app decides, in one value that `reduce` changes. The app target only draws it and carries out the
/// effects `reduce` returns, so every decision here has a test that runs on Linux.
public struct AppState: Equatable, Sendable {
    /// How long a source may report nothing before the notch hides: longer than the gap the adapter leaves between
    /// tracks, about half a second, so a skip doesn't close the notch under the pointer.
    public static let hideDelay: TimeInterval = 1.5

    /// What's playing as the notch shows it, which outlasts a source's report of nothing by `hideDelay`.
    public internal(set) var playback: PlaybackState?
    /// When `playback` goes after a report of nothing, or `nil` when no hide is pending.
    public internal(set) var hideAt: Date?
    /// Hides a paused track a while after the pause, unless the pointer is on a notch.
    public internal(set) var idle: IdleAfterPause
    /// Whether the pointer is on a notch or a card is open, which holds off Idle.
    public internal(set) var hovering = false
    /// One notch for each camera housing, real or virtual, by `NotchHousing.display`.
    public internal(set) var surfaces: [String: Surface] = [:]
    /// What a hover on the housing does while Idle.
    public internal(set) var idleHover: IdleHover
    /// Whether a Doctor check failed, which draws a resting notch with a "!" even when nothing is playing.
    public internal(set) var needsAttention = false
    /// The new track's title and artist, shown for a moment after a skip when Settings turns it on.
    public internal(set) var toasts = ToastQueue<TrackToast>()
    public internal(set) var showsTrackToast: Bool
    /// What the effects last asked for, so each is asked for once per change.
    public internal(set) var watchesClicks = false
    public internal(set) var takesEscape = false
    public internal(set) var followsVolume = false

    public init(stayVisibleAfterPausing: TimeInterval = IdleAfterPause.defaultDelay, idleHover: IdleHover = .lastPlayed, showsTrackToast: Bool = false) {
        idle = IdleAfterPause(delay: stayVisibleAfterPausing)
        self.idleHover = idleHover
        self.showsTrackToast = showsTrackToast
    }

    /// Whether the notches draw what's playing: something is, and it isn't Idle.
    public var showsPlayback: Bool { !idle.isIdle }

    /// The earliest time something changes if nothing else happens, or `nil` when nothing is due, so `Store` runs one
    /// timer at most, and none while nothing plays.
    public var deadline: Date? {
        ([hideAt, idle.deadline, toasts.deadline] + surfaces.values.map(\.hover.deadline)).compactMap { $0 }.min()
    }

    /// The state the notch over `display` draws.
    public func notchState(_ display: String) -> NotchState? {
        surfaces[display].map(notchState)
    }

    /// What the notch over `display` holds when Expanded.
    public func card(_ display: String) -> NotchCard? {
        surfaces[display].map(card)
    }

    func notchState(_ surface: Surface) -> NotchState {
        NotchState(
            surface.hover.state, isPlaying: showsPlayback, needsAttention: needsAttention, idleHover: idleHover,
            isAlwaysShown: surface.isAlwaysShown, showsToast: toasts.current != nil
        )
    }

    func card(_ surface: Surface) -> NotchCard {
        NotchCard(isPlaying: showsPlayback && playback != nil, needsAttention: needsAttention, showsDoctor: surface.showsDoctor)
    }

    /// Without anything playing, a "!" or a card to open while Idle, a notch draws nothing, or only a blank notch, and
    /// takes no hover or click.
    func answersPointer(_ surface: Surface) -> Bool {
        let state = notchState(surface)
        return state != .hidden && !(state == .idle && idleHover == .nothing)
    }

    /// One display's notch.
    public struct Surface: Equatable, Sendable {
        /// Whether the housing is one Warble draws on a display without a notch.
        public internal(set) var isVirtual: Bool
        /// Whether a blank notch stays drawn over the housing while nothing is playing.
        public internal(set) var isAlwaysShown: Bool
        public internal(set) var hover = HoverIntent()
        public internal(set) var pointerInside = false
        /// Whether the open card shows the Doctor's checks rather than the player, until the notch closes.
        public internal(set) var showsDoctor = false
        /// Whether a menu from this notch is open, which takes Escape for itself.
        public internal(set) var showsMenu = false

        init(_ housing: NotchHousing) {
            isVirtual = housing.isVirtual
            isAlwaysShown = housing.isAlwaysShown
        }
    }
}
