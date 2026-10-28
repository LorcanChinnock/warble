import Foundation

/// The notches, one for each camera housing: what the pointer has done to each and which card each shows. What they
/// draw also depends on what's playing, which they read through `SharedState`.
public struct Notches: Feature {
    /// One notch for each camera housing, real or virtual, by `NotchHousing.display`.
    public internal(set) var surfaces: [String: Surface] = [:]
    /// The displays that show a full-screen app, by `NotchDisplay.id`, whose notches draw nothing.
    public internal(set) var fullScreen: Set<String> = []

    /// Whether a virtual notch shows the title in its middle while something plays, which Settings turns on.
    public internal(set) var showsVirtualTitle = false

    /// When a virtual notch is there, which Settings chooses.
    public internal(set) var virtualVisibility = VirtualNotchVisibility.standard

    /// What the effects last asked for, so each is asked for once per change.
    public internal(set) var watchesClicks = false
    public internal(set) var takesEscape = false
    public internal(set) var followsVolume = false

    public init() {}

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
            handle(event, on: display, shared, at: now)
        case .menu(let display, let open):
            surfaces[display]?.showsMenu = open
            handle(open ? .menuOpened : .menuClosed, on: display, shared, at: now)
        case .dismiss(let except):
            dismiss(except: except, shared, at: now)
        case .virtualTitleChanged(let on):
            showsVirtualTitle = on
        case .virtualVisibilityChanged(let visibility):
            virtualVisibility = visibility
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
            }
        }
    }

    /// Asks for the effects that follow from which notches are open, each once when its reason changes.
    mutating func follow(_ shared: SharedState, at now: Date) -> [AppEffect] {
        let open = surfaces.values.filter { notchState($0, shared).isOpen }
        var effects: [AppEffect] = []
        // A click anywhere else closes an open notch, and so does Escape with the pointer on it. Both stop at rest, so a
        // resting notch watches nothing and never takes Escape from the app in front. Escape is let go while a menu is
        // open, so the key reaches the menu and closes it, and while the art is dragged out, so it cancels the drag.
        let watchesClicks = !open.isEmpty
        if watchesClicks != self.watchesClicks {
            self.watchesClicks = watchesClicks
            effects.append(.watchClicksOutside(watchesClicks))
        }
        let takesEscape = open.contains(where: \.pointerInside) && !surfaces.values.contains(where: \.showsMenu)
        if takesEscape != self.takesEscape {
            self.takesEscape = takesEscape
            effects.append(.takeEscape(takesEscape))
        }
        // Only the player has a slider and an output menu, not the note.
        let followsVolume = surfaces.values.contains { notchState($0, shared) == .expanded }
        if followsVolume != self.followsVolume {
            self.followsVolume = followsVolume
            effects.append(.followVolume(followsVolume))
        }
        return effects
    }

    // MARK: Selectors

    /// The state the notch draws.
    func notchState(_ surface: Surface, _ shared: SharedState) -> NotchState {
        let state = NotchState(surface.hover.state, isPlaying: shared.showsPlayback)
        // A full-screen app has the top of its display to itself.
        guard !surface.isFullScreen else { return .hidden }
        if surface.isVirtual, virtualVisibility == .off { return .hidden }
        if shared.showsPlayback { return state }
        // Nothing is playing. A real notch stays, empty, so pointing at it can say so; a virtual one only if Settings keeps it.
        if surface.isVirtual, virtualVisibility != .always { return .hidden }
        if surface.hover.state == .resting { return .empty }
        return shared.remembersTrack ? .recall : .note
    }

    /// Whether the notch draws the title in its middle. Only a virtual notch has room, since a real one's middle is the
    /// camera, and only while it shows a track, so with nothing playing it stays blank.
    func showsTitle(_ surface: Surface, _ shared: SharedState) -> Bool {
        showsVirtualTitle && surface.isVirtual && !surface.isFullScreen && shared.showsPlayback
            && shared.playback?.title.isEmpty == false
    }

    /// A notch that draws nothing takes no hover or click: a virtual one that isn't kept, or one over a full-screen app.
    /// An empty notch takes the hover that opens the note.
    func answersPointer(_ surface: Surface, _ shared: SharedState) -> Bool {
        guard !surface.isFullScreen else { return false }
        return notchState(surface, shared) != .hidden
    }

    /// Whether any notch is open.
    func isOpen(_ shared: SharedState) -> Bool {
        surfaces.values.contains { notchState($0, shared).isOpen }
    }

    /// Whether the pointer is on a notch or a card is open, which holds off Idle.
    func isHovered(_ shared: SharedState) -> Bool {
        surfaces.values.contains { notchState($0, shared).isOpen || $0.pointerInside }
    }

    // MARK: Helpers

    /// Passes `event` to the notch's `HoverIntent`, unless it takes no hover: a blank notch that doesn't open keeps none, so
    /// playback starting under the pointer doesn't open it.
    private mutating func handle(_ event: HoverEvent, on display: String, _ shared: SharedState, at now: Date) {
        guard let surface = surfaces[display], answersPointer(surface, shared) else { return }
        surfaces[display]?.hover.handle(event, at: now)
    }

    /// Keeps each open card open until `date` after the pointer leaves it.
    mutating func keepOpen(until date: Date, _ shared: SharedState, at now: Date) {
        for (display, surface) in surfaces where notchState(surface, shared).isOpen {
            surfaces[display]?.hover.handle(.keepOpen(until: date), at: now)
        }
    }

    private mutating func dismiss(except: String?, _ shared: SharedState, at now: Date) {
        for (display, surface) in surfaces where display != except && notchState(surface, shared).isOpen {
            surfaces[display]?.hover.handle(.dismiss, at: now)
        }
    }

    /// One display's notch.
    public struct Surface: Equatable, Sendable {
        /// Whether the housing is one Warble draws on a display without a notch.
        public internal(set) var isVirtual: Bool
        /// Whether the display shows a full-screen app, which hides its notch.
        public internal(set) var isFullScreen = false
        public internal(set) var hover = HoverIntent()
        public internal(set) var pointerInside = false
        /// Whether a menu from this notch is open, which takes Escape for itself.
        public internal(set) var showsMenu = false

        init(_ housing: NotchHousing) {
            isVirtual = housing.isVirtual
        }
    }
}
