import AppKit
import Observation
import WarbleCore

/// Warble's icon in the menu bar and the menu it opens. It's AppKit rather than SwiftUI's `MenuBarExtra`, because that
/// menu's items work out their own VoiceOver names, so a waiting update's item read its dot out as U+FFFC. `NotchMenu`
/// fills the menu, as it fills the notch's right-click menu, each time it opens, so the two can't drift apart and a
/// closed menu keeps nothing up to date.
@MainActor
final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let updater: Updater
    private let settingsWindow: SettingsWindow

    init(updater: Updater, settingsWindow: SettingsWindow) {
        self.updater = updater
        self.settingsWindow = settingsWindow
        super.init()
        menu.delegate = self
        item.menu = menu
        showIcon()
    }

    /// The bars, with a dot while an update waits. Reads only `pendingVersion`, so a download's progress doesn't redraw
    /// the icon.
    private func showIcon() {
        withObservationTracking {
            let waiting = updater.pendingVersion != nil
            item.button?.image = waiting ? .menuBarIconWithDot : .menuBarIcon
            item.button?.setAccessibilityLabel(AppMenuLabel.icon(updateWaiting: waiting))
        } onChange: { [weak self] in
            Task { @MainActor in self?.showIcon() }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        NotchMenu.fill(menu, source: nil, copyText: nil, updater: updater, settingsWindow: settingsWindow, openApp: {})
    }
}
