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
    /// The notches, one for each camera housing, and the settings they draw by.
    public internal(set) var notches: Notches
    /// One notch for each camera housing, real or virtual, by `NotchHousing.display`.
    public internal(set) var surfaces: [String: Surface] {
        get { notches.surfaces }
        set { notches.surfaces = newValue }
    }
    /// The displays that show a full-screen app, by `NotchDisplay.id`, whose notches draw nothing.
    public internal(set) var fullScreen: Set<String> {
        get { notches.fullScreen }
        set { notches.fullScreen = newValue }
    }
    /// The Doctor's checks behind the "!".
    public internal(set) var doctor: DoctorState
    /// Whether a Doctor check failed, which draws a resting notch with a "!" even when nothing is playing.
    public var needsAttention: Bool { doctor.needsAttention }
    /// The last track played, which the idle card shows. It outlasts what's playing, and Warble too.
    public internal(set) var last = LastPlayedState()
    public var lastPlayed: LastPlayed? { last.lastPlayed }
    /// The output's volume from 0 to 1, read while the player's card is open; `nil` when it can't be changed.
    public internal(set) var volume: Double?
    public internal(set) var isMuted = false
    /// The outputs to offer and the one playing, read while the player's card is open.
    public internal(set) var outputs: [AudioOutput] = []
    public internal(set) var currentOutput: UInt32?
    /// The new track's title and artist, shown for a moment after a skip when Settings turns it on.
    public internal(set) var toast: ToastState
    public var toasts: ToastQueue<TrackToast> { toast.queue }
    public internal(set) var showsTrackToast: Bool {
        get { toast.isOn }
        set { toast.isOn = newValue }
    }
    /// Whether a virtual notch shows the title in its middle while something plays, which Settings turns off.
    public internal(set) var showsVirtualTitle: Bool {
        get { notches.showsVirtualTitle }
        set { notches.showsVirtualTitle = newValue }
    }
    /// The first-run demo of the notch and the welcome window after it, which happen once, on a first launch.
    public internal(set) var onboarding = Onboarding()
    /// What the effects last asked for, so each is asked for once per change.
    public internal(set) var watchesClicks: Bool {
        get { notches.watchesClicks }
        set { notches.watchesClicks = newValue }
    }
    public internal(set) var takesEscape: Bool {
        get { notches.takesEscape }
        set { notches.takesEscape = newValue }
    }
    public internal(set) var followsVolume: Bool {
        get { notches.followsVolume }
        set { notches.followsVolume = newValue }
    }

    /// `checks` are what the Doctor finds before it has asked macOS anything: what it finds while the adapter works.
    public init(
        stayVisibleAfterPausing: TimeInterval = IdleAfterPause.defaultDelay,
        showsTrackToast: Bool = false, showsVirtualTitle: Bool = true,
        checks: [Doctor.Check] = []
    ) {
        idle = IdleAfterPause(delay: stayVisibleAfterPausing)
        doctor = DoctorState(checks: checks)
        notches = Notches(showsVirtualTitle: showsVirtualTitle)
        toast = ToastState(isOn: showsTrackToast)
    }

    /// Whether the notches draw what's playing: something is, and it isn't Idle.
    public var showsPlayback: Bool { !idle.isIdle }

    /// Where each part of the state keeps its deadline: a feature that can come due on its own adds one line here. Key paths
    /// rather than the features themselves, so asking for the deadline copies and boxes nothing.
    private static let deadlines: [any KeyPath<AppState, Date?> & Sendable] = [
        \.hideAt, \.idle.deadline, \.toast.deadline, \.onboarding.deadline,
        \.last.deadline, \.doctor.deadline, \.notches.deadline,
    ]

    /// The earliest time something changes if nothing else happens, or `nil` when nothing is due, so `Store` runs one
    /// timer at most, and none while nothing plays.
    public var deadline: Date? {
        Self.deadlines.compactMap { self[keyPath: $0] }.min()
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
        notches.notchState(surface, shared)
    }

    /// Whether the notch over `display` draws the title in its middle.
    public func titleInNotch(_ display: String) -> Bool {
        surfaces[display].map { notches.showsTitle($0, shared) } ?? false
    }

    /// When the first-run demo's preview track started while it shows one. The notches draw that track in place of
    /// `playback`, which stays what the sources said.
    public var demoTrackStart: Date? { onboarding.trackStart }

    /// Whether the notches draw a playing track: a real one, or the demo's.
    public var drawsPlayback: Bool { showsPlayback || demoTrackStart != nil }

    func card(_ surface: Surface) -> NotchCard {
        notches.card(surface, shared)
    }

    /// What the features may read of this state.
    var shared: SharedState {
        SharedState(
            playback: playback, showsPlayback: showsPlayback, hideAt: hideAt, needsAttention: needsAttention,
            hasToast: toasts.current != nil,
            demoState: onboarding.notchState, demoCard: onboarding.card
        )
    }

    func answersPointer(_ surface: Surface) -> Bool {
        notches.answersPointer(surface, shared)
    }

    public typealias Surface = Notches.Surface
}
