import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Built with the delegate, before the menu bar scene reads it.
    let environment = AppEnvironment()
    private var notch: NotchController?
    private var source: AdapterSource?
    private var fallback: ScriptSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // To see the notch without playing anything, launch with
        // `open build/WarbleDev.app --args -notchPreviewState resting` and hover or click it to open it; the argument
        // lasts only for that launch.
        let store = environment.store
        let runner = environment.runner
        let preview = Self.preview
        let notch = NotchController(environment: environment)
        if preview == .resting {
            let source = PreviewSource { [weak store] in store?.state.playback }
            runner.source = source
            Task {
                for await state in source.states {
                    store.dispatch(.playbackReported(state))
                }
            }
        } else if let paths = Bundle.main.resourceURL.flatMap(AdapterSource.Paths.init(resources:)) {
            let source = AdapterSource(paths: paths)
            source.start()
            runner.source = source
            Task {
                for await state in source.states {
                    store.dispatch(.playbackReported(state))
                }
                // The states end only when the adapter gives up.
                log.notice("The adapter gave up; following Music and Spotify with AppleScript (\(String(describing: source.backend), privacy: .public))")
                startFallback()
            }
            self.source = source
        } else {
            log.error("The adapter isn't in the app's resources; build with make bundle")
            startFallback()
        }
        self.notch = notch
        if let launch = Perf.millisecondsSinceLaunch() {
            Perf.signposter.emitEvent("Ready", "launch ms=\(launch)")
        }
        log.notice("Ready")
    }

    /// The preview the launch arguments ask for, if any.
    private static var preview: NotchState? {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        return (arguments["notchPreviewState"] as? String).flatMap(NotchState.init(rawValue:))
    }

    func applicationWillTerminate(_ notification: Notification) {
        source?.stop()
        fallback?.stop()
    }

    /// Follows Music and Spotify with AppleScript when the adapter can't run, so the two most common players still work.
    private func startFallback() {
        let fallback = ScriptSource()
        let store = environment.store
        fallback.start()
        environment.runner.source = fallback
        Task {
            for await state in fallback.states {
                store.dispatch(.playbackReported(state))
            }
        }
        self.fallback = fallback
    }

    /// Opening Warble again from Finder or Spotlight brings back a menu bar icon that was turned off, so it can always
    /// be reached, and opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.settingsWindow.show()
        return false
    }
}
