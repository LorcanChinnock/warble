import Foundation

/// How far the pointer has opened the notch.
public enum HoverState: String, CaseIterable, Sendable {
    /// The pointer is elsewhere, or only passing.
    case resting
    /// The pointer has stayed on the notch long enough to mean it, or the notch was clicked.
    case expanded
    /// Expanded, and stays open when the pointer leaves.
    case pinned
}

/// Something the pointer or the user did.
public enum HoverEvent: Sendable {
    /// The pointer entered the area that keeps the notch open: the camera housing itself while Idle or resting, not the
    /// wings, and the panel once it's open.
    case pointerEntered
    case pointerLeft
    case click
    case pinButton
    /// A click outside, or Escape.
    case dismiss
    /// A menu from the open card, such as the outputs, opened: the card stays open, wherever the pointer goes and
    /// whatever is clicked, until `menuClosed`.
    case menuOpened
    case menuClosed
}

/// Decides when the notch opens and closes, so moving the pointer past it on the way to a menu bar item never opens
/// Warble. It works the same whether anything is playing: while Idle, `.expanded` opens the idle card. It holds no timers: after each call the owner schedules one for `deadline`, if any, and calls
/// `advance(to:)` when it fires.
public struct HoverIntent: Equatable, Sendable {
    /// How long the pointer stays on the notch before it expands.
    public static let expandDelay: TimeInterval = 0.25
    /// How long after the pointer leaves the notch closes, unless pinned.
    public static let collapseDelay: TimeInterval = 0.4

    public private(set) var state = HoverState.resting
    /// When `state` changes next if nothing else happens, or `nil` when nothing is due.
    public private(set) var deadline: Date?
    private var pointerInside = false
    /// When the pointer started its stay on the notch; `nil` while it's away, and after a dismiss.
    private var enteredAt: Date?
    private var leftAt: Date?
    private var menuOpen = false

    public init() {}

    public mutating func handle(_ event: HoverEvent, at date: Date) {
        advance(to: date)
        switch event {
        case .pointerEntered:
            guard !pointerInside else { return }
            pointerInside = true
            enteredAt = date
            leftAt = nil
        case .pointerLeft:
            guard pointerInside else { return }
            pointerInside = false
            enteredAt = nil
            leftAt = date
        case .click:
            if state != .pinned { state = state == .expanded ? .pinned : .expanded }
        case .pinButton:
            state = state == .pinned ? .expanded : .pinned
            // Unpinned with the pointer away: the wait to close starts now, not when it left.
            if !pointerInside { leftAt = date }
        case .dismiss:
            guard !menuOpen else { return }
            state = .resting
            // Resting on the notch doesn't open it again until the pointer leaves and comes back; a click still does.
            enteredAt = nil
            leftAt = nil
        case .menuOpened:
            menuOpen = true
        case .menuClosed:
            guard menuOpen else { return }
            menuOpen = false
            // The pointer may have left long ago, over the menu: the wait to close starts now.
            if !pointerInside { leftAt = date }
        }
        deadline = nextDeadline()
    }

    /// Applies every deadline due by `date`.
    public mutating func advance(to date: Date) {
        while let due = deadline, due <= date {
            switch state {
            case .resting: state = .expanded
            case .expanded: state = .resting; leftAt = nil
            case .pinned: break
            }
            deadline = nextDeadline()
        }
    }

    private func nextDeadline() -> Date? {
        switch state {
        case .resting: enteredAt.map { $0 + Self.expandDelay }
        case .expanded: pointerInside || menuOpen ? nil : leftAt.map { $0 + Self.collapseDelay }
        case .pinned: nil
        }
    }
}
