import Foundation
import Observation
import os
import WarbleModel

private let log = Logger.warble("settings")

/// Settings › General › Show menu bar icon, on at first. `StatusItem` follows it, and turns it off when the icon is
/// ⌘-dragged off the menu bar. It's AppKit's alone, so the store never sees it.
@MainActor
@Observable
final class MenuBarIconSetting {
    private let defaults: UserDefaults

    var isShown: Bool {
        didSet {
            guard isShown != oldValue else { return }
            defaults.set(isShown, forKey: MenuBarIcon.shownKey)
            log.notice("Menu bar icon \(self.isShown ? "shown" : "hidden", privacy: .public)")
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isShown = defaults.object(forKey: MenuBarIcon.shownKey) as? Bool ?? true
    }
}
