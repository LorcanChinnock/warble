import Foundation

/// How far the pointer has opened the notch.
public enum HoverState: String, CaseIterable, Sendable {
    /// The pointer is elsewhere, or only passing.
    case resting
    /// The pointer has stayed on the notch long enough to mean it.
    case peeking
    case expanded
    /// Expanded, and stays open when the pointer leaves.
    case pinned
}

/// Something the pointer or the user did.
public enum HoverEvent: Sendable {
    /// The pointer entered the area that keeps the notch open: the notch itself while resting, not the wings, and
    /// the panel once it's open.
    case pointerEntered
    case pointerLeft
    case click
    case pinButton
    /// A click outside, or Escape.
    case dismiss
}

/// Decides when the notch opens and closes, so moving the pointer past it on the way to a menu bar item never opens
/// Warble. It holds no timers: after each call the owner schedules one for `deadline`, if any, and calls
/// `advance(to:)` when it fires.
public struct HoverIntent: Equatable, Sendable {
    /// How long the pointer stays on the notch before it peeks.
    public static let peekDelay: TimeInterval = 0.12
    /// How long the pointer stays on the notch before it expands, counted from when it entered.
    public static let expandDelay: TimeInterval = 0.6
    /// How long after the pointer leaves the notch closes, unless pinned.
    public static let collapseDelay: TimeInterval = 0.4

    public private(set) var state = HoverState.resting
    /// When `state` changes next if nothing else happens, or `nil` when nothing is due.
    public private(set) var deadline: Date?
    private var enteredAt: Date?
    private var leftAt: Date?

    public init() {}

    public mutating func handle(_ event: HoverEvent, at date: Date) {
        advance(to: date)
        switch event {
        case .pointerEntered:
            guard enteredAt == nil else { return }
            enteredAt = date
            leftAt = nil
        case .pointerLeft:
            guard enteredAt != nil else { return }
            enteredAt = nil
            leftAt = date
        case .click:
            if state != .pinned { state = state == .expanded ? .pinned : .expanded }
        case .pinButton:
            state = state == .pinned ? .expanded : .pinned
            // Unpinned with the pointer away: the wait to close starts now, not when it left.
            if enteredAt == nil { leftAt = date }
        case .dismiss:
            state = .resting
            // The pointer has to leave and come back before the notch opens again.
            enteredAt = nil
            leftAt = nil
        }
        deadline = nextDeadline()
    }

    /// Applies every deadline due by `date`.
    public mutating func advance(to date: Date) {
        while let due = deadline, due <= date {
            switch state {
            case .resting: state = .peeking
            case .peeking where enteredAt != nil: state = .expanded
            case .peeking, .expanded: state = .resting; leftAt = nil
            case .pinned: break
            }
            deadline = nextDeadline()
        }
    }

    private func nextDeadline() -> Date? {
        switch state {
        case .resting: enteredAt.map { $0 + Self.peekDelay }
        case .peeking: enteredAt.map { $0 + Self.expandDelay } ?? leftAt.map { $0 + Self.collapseDelay }
        case .expanded: enteredAt == nil ? leftAt.map { $0 + Self.collapseDelay } : nil
        case .pinned: nil
        }
    }
}
