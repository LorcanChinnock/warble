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
        // lasts only for that launch. `idle` shows the idle card with a preview track as the last played, and adding
        // `-notchPreviewLastPlayed NO` shows it with nothing played yet. Neither reads nor saves the real last track.
        let store = environment.store
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let preview = (arguments["notchPreviewState"] as? String).flatMap(NotchState.init(rawValue:))
        let isPreview = preview == .resting || preview == .idle
        let notch = NotchController(lastPlayedStore: isPreview ? nil : Bundle.main.bundleIdentifier.flatMap(LastPlayedStore.standard), environment: environment)
        if preview == .idle {
            if (arguments["notchPreviewLastPlayed"] as? String).map({ NSString(string: $0).boolValue }) ?? true {
                notch.lastPlayed = LastPlayed(bundleIdentifier: "com.apple.Music", appName: "Music", title: "Preview track with a title long enough to scroll", artist: "Preview artist")
            }
        } else if preview == .resting {
            store.dispatch(.playbackReported(PlaybackState(
                bundleIdentifier: "com.apple.Music",
                title: "Preview track with a title long enough to scroll",
                artist: "Preview artist",
                album: "Preview album",
                duration: 240,
                elapsed: 60,
                elapsedTimestamp: .now,
                rate: 1,
                shuffle: .off,
                repeatMode: .off
            )))
            // Next and previous change the preview track, such as from a shortcut, to show the track-change toast.
            var track = 1
            notch.send = { [weak store] command in
                guard let store, var playback = store.state.playback else { return }
                switch command {
                case .nextTrack: track += 1
                case .previousTrack: track = max(track - 1, 1)
                default: return
                }
                playback.title = "Preview track \(track) with a title long enough to scroll"
                store.dispatch(.playbackReported(playback))
            }
        } else if let paths = Bundle.main.resourceURL.flatMap(AdapterSource.Paths.init(resources:)) {
            let source = AdapterSource(paths: paths)
            source.start()
            notch.send = { command in Task { await source.send(command) } }
            Task {
                for await state in source.states {
                    store.dispatch(.playbackReported(state))
                }
                // The states end only when the adapter gives up.
                notch.doctor.adapter = .stopped(testStatus: source.lastTestStatus)
                startFallback(notch)
            }
            self.source = source
        } else {
            log.error("The adapter isn't in the app's resources; build with make bundle")
            notch.doctor.adapter = .missing
            startFallback(notch)
        }
        environment.hotkeys.onPress = { [weak notch] action in
            if let command = action.command {
                notch?.perform(command)
            } else {
                notch?.toggleKeyboard()
            }
        }
        environment.hotkeys.start()
        self.notch = notch
        if let launch = Perf.millisecondsSinceLaunch() {
            Perf.signposter.emitEvent("Ready", "launch ms=\(launch)")
        }
        log.notice("Ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        source?.stop()
        fallback?.stop()
    }

    /// Follows Music and Spotify with AppleScript when the adapter can't run, so the two most common players still work.
    private func startFallback(_ notch: NotchController) {
        let fallback = ScriptSource()
        fallback.onAutomationDenied = { [weak notch] in notch?.doctor.refresh() }
        fallback.start()
        notch.send = { command in Task { await fallback.send(command) } }
        Task {
            for await state in fallback.states {
                environment.store.dispatch(.playbackReported(state))
                notch.doctor.refreshIfAutomationFails()
            }
        }
        self.fallback = fallback
    }

    /// Opening Warble again from Finder or Spotlight brings back a menu bar icon that was turned off, so it can always
    /// be reached, and opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: PreferenceKey.showMenuBarIcon)
        environment.settingsWindow.show()
        return false
    }
}
