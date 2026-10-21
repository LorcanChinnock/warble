import Foundation

// What Settings calls WarbleModel's shortcut types. They live here because WarbleModel can't localize on Linux.

extension WarbleAction {
    public var title: String {
        switch self {
        case .playPause: String(localized: "Play or pause")
        case .nextTrack: String(localized: "Next track")
        case .previousTrack: String(localized: "Previous track")
        }
    }
}

extension WarbleAction.Conflict {
    /// Why `combo` was refused, short enough to sit under its row.
    public func message(for combo: KeyCombo) -> String {
        switch self {
        case .reserved: String(localized: "\(combo.displayString) is used by macOS and every app. Try another.")
        case .taken(let action): String(localized: "\(combo.displayString) is already set for \(action.title).")
        }
    }
}
