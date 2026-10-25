import Foundation

/// The notches, one for each camera housing: what the pointer has done to each, which card each shows, and the display
/// settings that decide how they draw. What they draw also depends on the other features (what's playing, a toast, the
/// lyrics, the Doctor, the first-run demo), which they read through `SharedState`.
public struct Notches: Feature {
    /// One notch for each camera housing, real or virtual, by `NotchHousing.display`.
    public internal(set) var surfaces: [String: Surface] = [:]
    /// The displays that show a full-screen app, by `NotchDisplay.id`, whose notches draw nothing.
    public internal(set) var fullScreen: Set<String> = []
    /// What a hover on the housing does while Idle.
    public internal(set) var idleHover: IdleHover
    /// Whether every notch is left out of screen sharing, recordings and screenshots, which Settings turns on. The
    /// window server does it, so nothing here watches for a capture and the notch draws the same either way.
    public internal(set) var hidesFromCapture: Bool
    /// Whether a virtual notch shows the title in its middle while something plays, which Settings turns off.
    public internal(set) var showsVirtualTitle: Bool

    /// What the effects last asked for, so each is asked for once per change.
    public internal(set) var watchesClicks = false
    public internal(set) var takesEscape = false
    public internal(set) var followsVolume = false

    public init(idleHover: IdleHover = .lastPlayed, hidesFromCapture: Bool = false, showsVirtualTitle: Bool = true) {
        self.idleHover = idleHover
        self.hidesFromCapture = hidesFromCapture
        self.showsVirtualTitle = showsVirtualTitle
    }

    /// When a hover next opens or closes a notch, or `nil` when none is due.
    var deadline: Date? { surfaces.values.compactMap(\.hover.deadline).min() }

    /// Handles what happens to the notches themselves: displays, the pointer, clicks, menus and the cards. What follows
    /// from the notches' states is settled afterwards.
    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        switch action {
        case .housingsChanged(let housings):
            var surfaces: [String: Surface] = [:]
            for housing in housings {
                var surface = self.surfaces[housing.display] ?? Surface(housing)
                surface.isVirtual = housing.isVirtual
                surface.isAlwaysShown = housing.isAlwaysShown
                surface.isFullScreen = fullScreen.contains(housing.display)
                surfaces[housing.display] = surface
            }
            self.surfaces = surfaces
        case .fullScreenChanged(let displays):
            // A notch that stops answering starts its hover over in `settle`, so an open card closes.
            fullScreen = displays
            for display in surfaces.keys {
                surfaces[display]?.isFullScreen = displays.contains(display)
            }
        case .pointer(let display, let inside):
            guard let surface = surfaces[display], answersPointer(surface, shared), inside != surface.pointerInside else { break }
            surfaces[display]?.pointerInside = inside
            handle(inside ? .pointerEntered : .pointerLeft, on: display, shared, at: now)
        case .hover(let display, let event):
            if event == .click || event == .keyboard {
                dismiss(except: display, shared, at: now)
            }
            if case .dragging(let dragging) = event {
                surfaces[display]?.isDragging = dragging
            }
            handle(event, on: display, shared, at: now)
        case .menu(let display, let open):
            surfaces[display]?.showsMenu = open
            handle(open ? .menuOpened : .menuClosed, on: display, shared, at: now)
        case .showDoctor(let display, let show):
            // From the resting "!", the click that follows opens the notch on the checks.
            surfaces[display]?.showsDoctor = show
        case .showLyrics(let display, let show):
            // Only from an open card, and only while there are lyrics to show; the button is there only then.
            guard let surface = surfaces[display], notchState(surface, shared) == .expanded, !show || shared.hasLyricsCard else { break }
            surfaces[display]?.showsLyrics = show
        case .dismiss(let except):
            dismiss(except: except, shared, at: now)
        case .idleHoverChanged(let idleHover):
            self.idleHover = idleHover
        case .hidesFromCaptureChanged(let on):
            hidesFromCapture = on
        case .virtualTitleChanged(let on):
            showsVirtualTitle = on
        case .tick:
            for display in surfaces.keys {
                surfaces[display]?.hover.advance(to: now)
            }
        default:
            break
        }
        return []
    }

    /// Brings the notches up to date with what the rest of the state did since `old`: a notch that stops answering the
    /// pointer starts its hover over, and one that closes shows the player again next time.
    mutating func settle(from old: Notches, oldShared: SharedState, shared: SharedState) {
        for (display, surface) in surfaces {
            guard let before = old.surfaces[display] else { continue }
            if old.answersPointer(before, oldShared), !answersPointer(surface, shared) {
                // Start over, so a pointer still on the notch when it's drawn again is reported as entering again.
                surfaces[display]?.hover = HoverIntent()
                surfaces[display]?.pointerInside = false
                surfaces[display]?.isDragging = false
            }
            if old.notchState(before, oldShared) == .expanded, notchState(surface, shared) != .expanded {
                // The checks and the lyrics show until the notch closes; the next open shows the player again.
                surfaces[display]?.showsDoctor = false
                surfaces[display]?.showsLyrics = false
            }
        }
    }

    /// Asks for the effects that follow from which notches are open, each once when its reason changes.
    mutating func follow(_ shared: SharedState, at now: Date) -> [AppEffect] {
        let open = surfaces.values.filter { notchState($0, shared) == .expanded }
        var effects: [AppEffect] = []
        // A click anywhere else closes an open notch, and so does Escape with the pointer on it. Both stop at rest, so a
        // resting notch watches nothing and never takes Escape from the app in front. Escape is let go while a menu is
        // open, so the key reaches the menu and closes it, and while the art is dragged out, so it cancels the drag.
        let watchesClicks = !open.isEmpty
        if watchesClicks != self.watchesClicks {
            self.watchesClicks = watchesClicks
            effects.append(.watchClicksOutside(watchesClicks))
        }
        let takesEscape = open.contains(where: \.pointerInside) && !surfaces.values.contains { $0.showsMenu || $0.isDragging }
        if takesEscape != self.takesEscape {
            self.takesEscape = takesEscape
            effects.append(.takeEscape(takesEscape))
        }
        // Only the player's card has a slider and an output menu.
        let followsVolume = open.contains { card($0, shared) == .player }
        if followsVolume != self.followsVolume {
            self.followsVolume = followsVolume
            effects.append(.followVolume(followsVolume))
        }
        return effects
    }

    // MARK: Selectors

    /// The state the notch draws. The first-run demo draws over every notch until it ends.
    func notchState(_ surface: Surface, _ shared: SharedState) -> NotchState {
        let state = shared.demoState ?? NotchState(
            surface.hover.state, isPlaying: shared.showsPlayback, needsAttention: shared.needsAttention, idleHover: idleHover,
            isAlwaysShown: surface.isAlwaysShown, showsToast: shared.hasToast && !showsTitle(surface, shared),
            showsLyrics: shared.showsLyricsLine
        )
        // A full-screen app has the top of its display to itself, apart from the toast when Settings lets it through.
        guard surface.isFullScreen else { return state }
        return state == .toast && shared.toastsInFullScreen ? .toast : .hidden
    }

    /// What the notch holds when Expanded.
    func card(_ surface: Surface, _ shared: SharedState) -> NotchCard {
        shared.demoCard ?? NotchCard(
            isPlaying: shared.showsPlayback && shared.playback != nil, needsAttention: shared.needsAttention,
            showsDoctor: surface.showsDoctor, showsLyrics: surface.showsLyrics && shared.hasLyricsCard
        )
    }

    /// Only a virtual notch has room for the title, since a real one's middle is the camera. It scrolls the title once for
    /// each track, which says what a track-change toast would, so the toast leaves it alone. Over a full-screen app the
    /// notch is hidden, so the toast, if Settings lets it through, stays.
    func showsTitle(_ surface: Surface, _ shared: SharedState) -> Bool {
        showsVirtualTitle && surface.isVirtual && !surface.isFullScreen && shared.showsPlayback && shared.playback?.title.isEmpty == false
    }

    /// Without anything playing, a "!" or a card to open while Idle, a notch draws nothing, or only a blank notch, and
    /// takes no hover or click. Nor does one over a full-screen app, so a toast there can't open the card.
    func answersPointer(_ surface: Surface, _ shared: SharedState) -> Bool {
        guard !surface.isFullScreen else { return false }
        let state = notchState(surface, shared)
        return state != .hidden && !(state == .idle && idleHover == .nothing)
    }

    /// Whether any notch draws the play-state bars: it's resting, or has a toast or a lyric line under it.
    func drawsBars(_ shared: SharedState) -> Bool {
        surfaces.values.contains { [.resting, .toast, .lyrics].contains(notchState($0, shared)) }
    }

    /// Whether any notch is open.
    func isOpen(_ shared: SharedState) -> Bool {
        surfaces.values.contains { notchState($0, shared) == .expanded }
    }

    /// Whether the pointer is on a notch or a card is open, which holds off Idle.
    func isHovered(_ shared: SharedState) -> Bool {
        surfaces.values.contains { notchState($0, shared) == .expanded || $0.pointerInside }
    }

    // MARK: Helpers

    /// Passes `event` to the notch's `HoverIntent`, unless it takes no hover: a blank notch that doesn't open keeps none, so
    /// playback starting under the pointer doesn't open it.
    private mutating func handle(_ event: HoverEvent, on display: String, _ shared: SharedState, at now: Date) {
        guard let surface = surfaces[display], answersPointer(surface, shared) else { return }
        surfaces[display]?.hover.handle(event, at: now)
    }

    private mutating func dismiss(except: String?, _ shared: SharedState, at now: Date) {
        for (display, surface) in surfaces where display != except && notchState(surface, shared) == .expanded {
            surfaces[display]?.hover.handle(.dismiss, at: now)
        }
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
