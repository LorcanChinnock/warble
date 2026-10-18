import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        _ = Updater.shared
        log.notice("Ready")
    }

    /// Opening Warble again from Finder or Spotlight brings back a menu bar icon that was turned off, so it can always
    /// be reached.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: PreferenceKey.showMenuBarIcon)
        return false
    }
}
