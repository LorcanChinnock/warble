import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

/// Carries out the effects that need AppKit or a Mac-only framework, and sends what they find back to the store.
@MainActor
final class PlatformEffects {
    private let dispatch: (AppAction) -> Void
    /// Opens or closes the notch with the keyboard. The notch sets it, since it knows which notch the pointer is on.
    var toggleKeyboard: () -> Void = {}
    /// Opens the welcome window, which `AppEnvironment` sets once it's built.
    var showWelcome: () -> Void = {}
    private var clickMonitor: Any?
    private var playerObservers: [NSObjectProtocol] = []

    init(dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
    }

    func perform(_ effect: AppEffect) {
        switch effect {
        case .watchClicksOutside(let watch):
            watchClicksOutside(watch)
        case .openApp(let bundleIdentifier):
            // Brings the app to the front, opening it if it's quit.
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .launchAndPlay(let player):
            Task {
                // A refused script (Automation turned off) still leaves the app open, which is the old behaviour.
                if await !ScriptSource.launchAndPlay(player) {
                    perform(.openApp(bundleIdentifier: player.bundleIdentifier))
                }
            }
        case .openLink(let url, let bundleIdentifier):
            // The browser the track played in, if it's still installed, otherwise whatever handles the link.
            if let bundleIdentifier, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        case .haptic:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        case .gatherFacts(let adapter, let pass):
            let dispatch = dispatch
            Task {
                dispatch(.factsGathered(await Doctor.facts(adapter: adapter), pass: pass))
            }
        case .followPlayers(let follow):
            followPlayers(follow)
        case .toggleKeyboard:
            toggleKeyboard()
        case .showWelcome:
            showWelcome()
        case .turnOffWaveform:
            // macOS said no, so the setting says so too, until it's turned on again.
            UserDefaults.standard.set(false, forKey: PreferenceKey.waveform)
            UserDefaults.standard.set(true, forKey: PreferenceKey.waveformRefused)
            log.notice("The waveform turned itself off: macOS wouldn't let Warble hear the Mac's audio")
        default:
            break
        }
    }

    /// Clicks in other apps close the open notches; a click on the panel itself is the panel's own.
    private func watchClicksOutside(_ watch: Bool) {
        if watch, clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.dispatch(.dismiss(except: nil)) }
            }
        } else if !watch, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    /// Music and Spotify opening or quitting changes what macOS says about Automation, and what the fallback can follow.
    private func followPlayers(_ follow: Bool) {
        let following = !playerObservers.isEmpty
        guard follow != following else { return }
        guard follow else {
            playerObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            playerObservers = []
            return
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            playerObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier.flatMap(ScriptedPlayer.init(rawValue:)) != nil else { return }
                MainActor.assumeIsolated { self?.dispatch(.playersChanged) }
            })
        }
    }
}
