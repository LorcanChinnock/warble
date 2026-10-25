import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Built with the delegate, before the menu bar scene reads it.
    let environment = AppEnvironment(lastPlayed: AppDelegate.lastPlayedStore(), lyrics: AppDelegate.lyricsProvider(), stats: AppDelegate.statsStore())
    private var notch: NotchController?
    private var source: AdapterSource?
    private var fallback: ScriptSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // To see the notch without playing anything, launch with
        // `open build/WarbleDev.app --args -notchPreviewState resting` and hover or click it to open it; the argument
        // lasts only for that launch. `idle` shows the idle card with a preview track as the last played, and adding
        // `-notchPreviewLastPlayed NO` shows it with nothing played yet. Neither reads nor saves the real last track.
        // `activity` is `resting` with a made-up activity from another app over the music; `-notchPreviewActivities 3` shows three.
        let store = environment.store
        let runner = environment.runner
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let preview = Self.preview
        let notch = NotchController(environment: environment)
        runner.loadLastPlayed()
        if preview == .idle {
            if (arguments["notchPreviewLastPlayed"] as? String).map({ NSString(string: $0).boolValue }) ?? true {
                store.dispatch(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.apple.Music", appName: "Music", title: "Preview track with a title long enough to scroll", artist: "Preview artist")))
            }
        } else if Self.isPreviewingPlayback {
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
                store.dispatch(.adapterChanged(Doctor.Adapter(source.backend)))
                startFallback()
            }
            self.source = source
        } else {
            log.error("The adapter isn't in the app's resources; build with make bundle")
            store.dispatch(.adapterChanged(Doctor.Adapter(AdapterSupervisor(bundled: false).backend)))
            startFallback()
        }
        if preview == .activity {
            PreviewActivities.start(arguments["notchPreviewActivities"].flatMap { Int("\($0)") } ?? 1, in: store)
        }
        environment.hotkeys.onPress = { [weak store] action in store?.dispatch(.perform(action)) }
        environment.hotkeys.start()
        self.notch = notch
        // The previews are for looking at the notch, so they skip the welcome window. Reads the saved domain, since
        // `UserDefaults` also answers with registered defaults.
        if preview == nil {
            let saved = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:)) ?? [:]
            store.dispatch(.launched(firstRun: Preferences.isFirstLaunch(saved: saved)))
        }
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

    /// Whether the launch arguments ask for a preview with a track that plays without a player.
    private static var isPreviewingPlayback: Bool { preview == .resting || preview == .activity }

    /// Where the last track played is kept across launches, or only in memory for the preview, which neither reads nor
    /// saves the real one.
    private static func lastPlayedStore() -> any LastPlayedStore {
        guard !isPreviewingPlayback, preview != .idle, let file = Bundle.main.bundleIdentifier.flatMap(LastPlayedFile.standard) else {
            return LastPlayedInMemory()
        }
        return file
    }

    /// Where the listening stats are kept across launches, or only in memory for the preview, which writes none.
    private static func statsStore() -> any StatsStore {
        guard !isPreviewingPlayback, preview != .idle, let file = Bundle.main.bundleIdentifier.flatMap(StatsFile.standard) else {
            return StatsInMemory()
        }
        return file
    }

    /// LRCLIB, with its cache in Caches, or for the preview a few made-up lines, so the preview sends nothing.
    private static func lyricsProvider() -> (any LyricsProvider)? {
        guard !isPreviewingPlayback else { return PreviewLyrics() }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return LRCLIBClient.standard(bundleIdentifier: bundleIdentifier, version: version)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Counts the track playing, and waits for the write, since nothing runs after this.
        environment.store.dispatch(.willQuit)
        environment.runner.flushStats()
        environment.platform.stopListening()
        source?.stop()
        fallback?.stop()
    }

    /// Follows Music and Spotify with AppleScript when the adapter can't run, so the two most common players still work.
    private func startFallback() {
        let fallback = ScriptSource()
        let store = environment.store
        fallback.onAutomationDenied = { [weak store] in store?.dispatch(.automationDenied) }
        fallback.start()
        environment.runner.source = fallback
        Task {
            for await state in fallback.states {
                store.dispatch(.playbackReported(state))
                store.dispatch(.fallbackReported)
            }
        }
        self.fallback = fallback
    }

    /// A `warble://` link, from Terminal's `open`, a launcher or a script. It's one more way in for the same commands as
    /// the notch's buttons, and `reduce` ignores it while the Developer card has links off.
    func application(_ application: NSApplication, open urls: [URL]) {
        let store = environment.store
        for url in urls {
            guard let scheme = url.scheme?.lowercased(), RemoteCommand.schemes.contains(scheme) else { continue }
            guard store.state.answersLinks else {
                log.notice("Ignored a link: links are off in Settings › Developer")
                continue
            }
            guard let command = RemoteCommand(url: url) else {
                log.notice("Ignored a link that isn't a route Warble knows")
                environment.toast.error("That link isn't one Warble knows. The guide lists the ones it does.")
                continue
            }
            store.dispatch(.linkOpened(command))
        }
    }

    /// Opening Warble again from Finder or Spotlight brings back a menu bar icon that was turned off, so it can always
    /// be reached, and opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: PreferenceKey.showMenuBarIcon)
        environment.settingsWindow.show()
        return false
    }
}
