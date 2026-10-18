import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        _ = Updater.shared
        let notch = NotchController()
        // Nothing is playing until playback is read (#9). To see the notch now, launch with
        // `open build/WarbleDev.app --args -notchPreviewState resting` and hover or click it to open it; the argument
        // lasts only for that launch.
        let preview = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["notchPreviewState"] as? String
        if preview.flatMap(NotchState.init(rawValue:)) == .resting {
            notch.playback = PlaybackState(
                bundleIdentifier: "com.apple.Music",
                title: "Preview track with a title long enough to scroll",
                artist: "Preview artist",
                album: "Preview album",
                duration: 240,
                elapsed: 60,
                elapsedTimestamp: .now,
                rate: 1
            )
        }
        self.notch = notch
        if let launch = Perf.millisecondsSinceLaunch() {
            Perf.signposter.emitEvent("Ready", "launch ms=\(launch)")
        }
        log.notice("Ready")
    }

    /// Opening Warble again from Finder or Spotlight brings back a menu bar icon that was turned off, so it can always
    /// be reached.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: PreferenceKey.showMenuBarIcon)
        return false
    }
}
