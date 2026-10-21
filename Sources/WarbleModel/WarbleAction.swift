import Foundation

/// What a global shortcut can do. New actions go last, since `HotkeyCenter` numbers hotkeys by position.
public enum WarbleAction: String, CaseIterable, Sendable {
    case playPause = "play-pause"
    case nextTrack = "next-track"
    case previousTrack = "previous-track"

    /// None by default: the keyboard's media keys already do these, and a global shortcut would take its keys from
    /// every app.
    public var defaultCombo: KeyCombo? {
        switch self {
        case .playPause, .nextTrack, .previousTrack: nil
        }
    }

    /// What the action asks the playing app to do.
    public var command: PlaybackCommand {
        switch self {
        case .playPause: .togglePlayPause
        case .nextTrack: .nextTrack
        case .previousTrack: .previousTrack
        }
    }

    /// Why `combo` can't be this action's shortcut.
    public enum Conflict: Equatable, Sendable {
        /// macOS or every app uses it: quit, close, switch apps, Spotlight, hide or minimise.
        case reserved
        /// Another of Warble's actions has it.
        case taken(by: WarbleAction)
    }

    /// Shortcuts Warble never takes, since a global one would steal them from every app.
    /// ⌘Q, ⌘W, ⌘Tab, ⌘Space, ⌘H and ⌘M.
    public static let reservedCombos = Set([12, 13, 48, 49, 4, 46].map { KeyCombo(keyCode: $0, modifiers: KeyCombo.command) })

    /// Why `combo` can't be this action's shortcut given Warble's `bindings`, or `nil` when it can. Only Warble's own
    /// shortcuts and the reserved ones are checked; other apps' aren't known.
    public func conflict(for combo: KeyCombo, bindings: [WarbleAction: KeyCombo]) -> Conflict? {
        if Self.reservedCombos.contains(combo) {
            return .reserved
        }
        // In `allCases` order, so the answer doesn't depend on the dictionary's.
        return Self.allCases.first { $0 != self && bindings[$0] == combo }.map { .taken(by: $0) }
    }
}
