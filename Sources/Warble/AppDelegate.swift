import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    private var source: AdapterSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        _ = Updater.shared
        let notch = NotchController()
        // To see the notch without playing anything, launch with
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
        } else if let paths = Bundle.main.resourceURL.flatMap(AdapterSource.Paths.init(resources:)) {
            let source = AdapterSource(paths: paths)
            source.start()
            Task {
                for await state in source.states {
                    notch.playback = state
                }
            }
            self.source = source
        } else {
            log.error("The adapter isn't in the app's resources, so nothing will show; build with make bundle")
        }
        self.notch = notch
        if let launch = Perf.millisecondsSinceLaunch() {
            Perf.signposter.emitEvent("Ready", "launch ms=\(launch)")
        }
        log.notice("Ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        source?.stop()
    }

    /// Opening Warble again from Finder or Spotlight brings back a menu bar icon that was turned off, so it can always
    /// be reached.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: PreferenceKey.showMenuBarIcon)
        return false
    }
}
