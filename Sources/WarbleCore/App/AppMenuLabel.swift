import Foundation
import WarbleModel

public extension UpdateMenuItem {
    /// The update item's title in the menus.
    var title: String {
        switch self {
        case .check:
            String(localized: "Check for Updates…")
        case .waiting(let version):
            String(localized: "Update to \(version)…")
        case .downloading(let version, nil):
            String(localized: "Downloading \(version)…", comment: "A menu item while an update downloads and its size isn't known.")
        case .downloading(let version, let percent?):
            String(
                localized: "Downloading \(version) (\((Double(percent) / 100).formatted(.percent)))…",
                comment: "A menu item while an update downloads: “Downloading 0.2.0 (53%)…”. Choosing it shows the update window."
            )
        }
    }
}

public enum AppMenuLabel {
    /// The menu bar icon's VoiceOver name.
    public static func icon(updateWaiting: Bool) -> String {
        updateWaiting
            ? String(localized: "Warble, update available", comment: "VoiceOver's name for the menu bar icon while an update waits.")
            : "Warble"
    }
}
