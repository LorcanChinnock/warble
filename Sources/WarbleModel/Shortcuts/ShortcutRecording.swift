import Foundation

/// What a key pressed while Settings records an action's shortcut does.
public enum ShortcutRecording: Equatable, Sendable {
    /// Escape: stop recording and keep the shortcut as it was.
    case cancel
    /// Delete or Forward Delete on its own: remove the shortcut.
    case clear
    /// A key with no modifier, or only ⇧, which would take ordinary typing from every app. Keep recording.
    case needsModifier
    /// The combo can't be this action's shortcut, so the old one stays.
    case refused(WarbleAction.Conflict)
    /// The action's new shortcut.
    case record(KeyCombo)

    static let escape: UInt32 = 53
    static let delete: UInt32 = 51
    static let forwardDelete: UInt32 = 117

    /// What pressing `combo` does while recording `action`'s shortcut, given Warble's current `bindings`.
    public init(_ combo: KeyCombo, for action: WarbleAction, bindings: [WarbleAction: KeyCombo]) {
        let modifiers = combo.modifiers & (KeyCombo.command | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        if combo.keyCode == Self.escape, modifiers == 0 {
            self = .cancel
        } else if combo.keyCode == Self.delete || combo.keyCode == Self.forwardDelete, modifiers == 0 {
            self = .clear
        } else if modifiers & ~KeyCombo.shift == 0 {
            self = .needsModifier
        } else {
            let combo = KeyCombo(keyCode: combo.keyCode, modifiers: modifiers)
            self = action.conflict(for: combo, bindings: bindings).map(Self.refused) ?? .record(combo)
        }
    }
}
