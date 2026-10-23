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
    /// The displays that show a full-screen app, by `NotchDisplay.id`, whose notches draw nothing.
    public internal(set) var fullScreen: Set<String> = []
    /// What a hover on the housing does while Idle.
    public internal(set) var idleHover: IdleHover
    /// The Doctor's checks behind the "!".
    public internal(set) var doctor: DoctorState
    /// Whether a Doctor check failed, which draws a resting notch with a "!" even when nothing is playing.
    public var needsAttention: Bool { doctor.needsAttention }
    /// The last track played, which the idle card shows. It outlasts what's playing, and Warble too.
    public internal(set) var lastPlayed: LastPlayed?
    /// The state last remembered, so a pause or a seek doesn't remember it again.
    public internal(set) var remembered: PlaybackState?
    /// Bumped by every track remembered, so one whose art finishes shrinking after the next has begun is dropped.
    public internal(set) var remembers = 0
    /// The output's volume from 0 to 1, read while the player's card is open; `nil` when it can't be changed.
    public internal(set) var volume: Double?
    public internal(set) var isMuted = false
    /// The outputs to offer and the one playing, read while the player's card is open.
    public internal(set) var outputs: [AudioOutput] = []
    public internal(set) var currentOutput: UInt32?
    /// The new track's title and artist, shown for a moment after a skip when Settings turns it on.
    public internal(set) var toasts = ToastQueue<TrackToast>()
    public internal(set) var showsTrackToast: Bool
    /// Whether the toast also shows over a full-screen app, which Settings turns on.
    public internal(set) var toastsInFullScreen: Bool
    /// The current lyric line, which a resting notch shows under it when Settings turns lyrics on.
    public internal(set) var lyrics: LyricsState
    /// Whether a sideways swipe over a notch skips, which Settings turns on, and the trackpad gesture under way.
    public internal(set) var swipeToSkip: Bool
    public internal(set) var swipe = Swipe()
    /// Whether a podcast or audiobook skips by seconds rather than by track, which Settings turns on.
    public internal(set) var podcastSkips: Bool
    /// Whether the player's card has a sleep timer button, which Settings turns on, and the timer running, if any.
    public internal(set) var showsSleepTimer: Bool
    public internal(set) var sleepTimer: SleepTimer?
    /// Whether the art can be dragged out of the player's card, which Settings turns on.
    public internal(set) var dragArtOut: Bool
    /// Whether every notch is left out of screen sharing, recordings and screenshots, which Settings turns on. The
    /// window server does it, so nothing here watches for a capture and the notch draws the same either way.
    public internal(set) var hidesFromCapture: Bool
    /// Whether a virtual notch shows the title in its middle while something plays, which Settings turns off.
    public internal(set) var showsVirtualTitle: Bool
    /// Whether `warble://` links do anything, which the Developer card in Settings turns on.
    public internal(set) var answersLinks: Bool
    /// Whether Warble answers the `warble` command line, which the Developer card turns on. Off, no socket is open.
    public internal(set) var listensForCommands: Bool
    /// The first-run demo of the notch and the welcome window after it, which happen once, on a first launch.
    public internal(set) var onboarding = Onboarding()
    /// What the effects last asked for, so each is asked for once per change.
    public internal(set) var watchesClicks = false
    public internal(set) var takesEscape = false
    public internal(set) var followsVolume = false
    public internal(set) var listening = false

    /// `checks` are what the Doctor finds before it has asked macOS anything: what it finds while the adapter works.
    public init(
        stayVisibleAfterPausing: TimeInterval = IdleAfterPause.defaultDelay, idleHover: IdleHover = .lastPlayed,
        showsTrackToast: Bool = false, toastsInFullScreen: Bool = false, showsLyrics: Bool = false, swipeToSkip: Bool = false, podcastSkips: Bool = false,
        dragArtOut: Bool = false, showsSleepTimer: Bool = false, hidesFromCapture: Bool = false, showsVirtualTitle: Bool = true,
        answersLinks: Bool = false, listensForCommands: Bool = false,
        checks: [Doctor.Check] = []
    ) {
        idle = IdleAfterPause(delay: stayVisibleAfterPausing)
        doctor = DoctorState(checks: checks)
        self.idleHover = idleHover
        self.showsTrackToast = showsTrackToast
        self.toastsInFullScreen = toastsInFullScreen
        self.swipeToSkip = swipeToSkip
        self.podcastSkips = podcastSkips
        self.dragArtOut = dragArtOut
        self.showsSleepTimer = showsSleepTimer
        self.hidesFromCapture = hidesFromCapture
        self.showsVirtualTitle = showsVirtualTitle
        self.answersLinks = answersLinks
        self.listensForCommands = listensForCommands
        lyrics = LyricsState(isOn: showsLyrics)
    }

    /// Whether the notches draw what's playing: something is, and it isn't Idle.
    public var showsPlayback: Bool { !idle.isIdle }

    /// The earliest time something changes if nothing else happens, or `nil` when nothing is due, so `Store` runs one
    /// timer at most, and none while nothing plays.
    public var deadline: Date? {
        ([hideAt, idle.deadline, toasts.deadline, lyrics.deadline, onboarding.demo.deadline, sleepTimer?.deadline] + surfaces.values.map(\.hover.deadline)).compactMap { $0 }.min()
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
        let state = demoState ?? NotchState(
            surface.hover.state, isPlaying: showsPlayback, needsAttention: needsAttention, idleHover: idleHover,
            isAlwaysShown: surface.isAlwaysShown, showsToast: toasts.current != nil && !showsTitle(surface),
            showsLyrics: lyrics.showsLine
        )
        // A full-screen app has the top of its display to itself, apart from the toast when Settings lets it through.
        guard surface.isFullScreen else { return state }
        return state == .toast && toastsInFullScreen ? .toast : .hidden
    }

    /// Whether the notch over `display` draws the title in its middle.
    public func titleInNotch(_ display: String) -> Bool {
        surfaces[display].map(showsTitle) ?? false
    }

    /// Only a virtual notch has room, since a real one's middle is the camera. It scrolls the title once for each track,
    /// which says what a track-change toast would, so the toast leaves it alone. Over a full-screen app the notch is
    /// hidden, so the toast, if Settings lets it through, stays.
    func showsTitle(_ surface: Surface) -> Bool {
        showsVirtualTitle && surface.isVirtual && !surface.isFullScreen && showsPlayback && playback?.title.isEmpty == false
    }

    /// What the first-run demo draws on every notch while it runs, ahead of what's really playing: it never starts with
    /// something playing and ends when something does.
    var demoState: NotchState? {
        switch onboarding.demo.step {
        case .resting: .resting
        case .expanded: .expanded
        case .hint: .hint
        case nil: nil
        }
    }

    func card(_ surface: Surface) -> NotchCard {
        if onboarding.demo.step == .expanded { return .player }
        return NotchCard(
            isPlaying: showsPlayback && playback != nil, needsAttention: needsAttention, showsDoctor: surface.showsDoctor,
            showsLyrics: surface.showsLyrics && hasLyricsCard
        )
    }

    /// Whether there's a lyrics card to show, which the player's card offers: the song playing has lyrics, which only
    /// happens with lyrics on in Settings.
    public var hasLyricsCard: Bool {
        showsPlayback && playback != nil && lyrics.excerpt != nil
    }

    /// Whether the player's card skips back and forward by seconds rather than by track: Settings turns it on, and a
    /// podcast or audiobook is playing, with a length to move through.
    public var skipsBySeconds: Bool {
        guard podcastSkips, showsPlayback, let playback, playback.duration != nil else { return false }
        return SpokenWord.contains(playback)
    }

    /// Whether a sleep timer can run now: Settings has it on and something is playing, not about to be hidden.
    public var canSetSleepTimer: Bool {
        hideAt == nil && keepsSleepTimer
    }

    /// Whether a running sleep timer stays: Settings has it on and something is playing. It outlasts the gap a source
    /// leaves between tracks (`hideAt`), since the next track's report is what ends an End of track timer.
    var keepsSleepTimer: Bool {
        showsSleepTimer && showsPlayback && playback?.isPlaying == true
    }

    /// What dragging the art out of the player's card carries, or `nil` when it can't be dragged: Settings has it off,
    /// nothing is playing, or the track has neither a link nor art.
    public var artDrag: ArtDrag? {
        guard dragArtOut, showsPlayback, let playback else { return nil }
        return ArtDrag(playback)
    }

    /// Without anything playing, a "!" or a card to open while Idle, a notch draws nothing, or only a blank notch, and
    /// takes no hover or click. Nor does one over a full-screen app, so a toast there can't open the card.
    func answersPointer(_ surface: Surface) -> Bool {
        guard !surface.isFullScreen else { return false }
        let state = notchState(surface)
        return state != .hidden && !(state == .idle && idleHover == .nothing)
    }

    /// One display's notch.
    public struct Surface: Equatable, Sendable {
        /// Whether the housing is one Warble draws on a display without a notch.
        public internal(set) var isVirtual: Bool
        /// Whether a blank notch stays drawn over the housing while nothing is playing.
        public internal(set) var isAlwaysShown: Bool
        /// Whether the display shows a full-screen app, which hides its notch.
        public internal(set) var isFullScreen = false
        public internal(set) var hover = HoverIntent()
        public internal(set) var pointerInside = false
        /// Whether the open card shows the Doctor's checks rather than the player, until the notch closes.
        public internal(set) var showsDoctor = false
        /// Whether the open card shows the lyrics rather than the player, until the notch closes.
        public internal(set) var showsLyrics = false
        /// Whether a menu from this notch is open, which takes Escape for itself.
        public internal(set) var showsMenu = false
        /// Whether the art is being dragged out of this notch's card, which lets go of Escape so the key cancels the drag.
        public internal(set) var isDragging = false

        init(_ housing: NotchHousing) {
            isVirtual = housing.isVirtual
            isAlwaysShown = housing.isAlwaysShown
        }
    }
}

/// The Doctor's checks for every notch, and the "!" they put on it when one fails. It checks again only when something
/// changes: the adapter stops, a player opens or quits, macOS refuses a script, or a notch opens. While the adapter
/// works every check passes without asking macOS anything.
public struct DoctorState: Equatable, Sendable {
    /// The adapter as the app last saw it. Anything but `.working` follows players opening and quitting.
    public internal(set) var adapter = Doctor.Adapter.working
    public internal(set) var checks: [Doctor.Check]
    /// The failures the user put off with Not now, until Warble opens again or another check fails.
    public internal(set) var dismissed: Set<Doctor.Kind> = []
    /// Bumped by every refresh, so facts that arrive after a later refresh has begun are dropped.
    public internal(set) var refreshes = 0

    public var needsAttention: Bool {
        Doctor.needsAttention(checks, dismissed: dismissed)
    }

    init(checks: [Doctor.Check]) {
        self.checks = checks
    }
}
