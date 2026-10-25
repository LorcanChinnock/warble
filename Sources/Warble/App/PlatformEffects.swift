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
    /// Opens Settings on the section with this name, which `AppEnvironment` sets once the window exists.
    var openSettings: (String?) -> Void = { _ in }
    /// Answers a request from the `warble` command, which `AppEnvironment` sets.
    var commandHandler: @Sendable (RemoteRequest) async -> RemoteResponse = { _ in .failure(.unavailable("Warble isn't ready")) }
    /// Tells the user something went wrong that the effect can't fix, as a toast, which `AppEnvironment` sets.
    var showError: (String) -> Void = { _ in }
    /// The socket other apps show activities over, and the handler that answers their lines, which `AppEnvironment` sets.
    /// `nil` where Warble has no folder to make the socket in.
    var activitySocket: ActivitySocket?
    var activityHandler: ActivityHandler?
    private var commandServer: AgentSocket.Server?
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
        case .openSettings(let section):
            openSettings(section)
        case .listenForCommands(let listen):
            listenForCommands(listen)
        case .listenForActivities(let listen):
            listenForActivities(listen)
        case .saveActivityApps(let apps):
            UserDefaults.standard.set(apps, forKey: PreferenceKey.activityApps)
        case .turnOffWaveform:
            // macOS said no, so the setting says so too, until it's turned on again.
            UserDefaults.standard.set(false, forKey: PreferenceKey.waveform)
            UserDefaults.standard.set(true, forKey: PreferenceKey.waveformRefused)
            log.notice("The waveform turned itself off: macOS wouldn't let Warble hear the Mac's audio")
        default:
            break
        }
    }

    /// Opens the socket the `warble` command talks to, or closes it, so while the setting is off no socket exists.
    private func listenForCommands(_ listen: Bool) {
        guard listen else {
            // Only the command line's socket: the activities socket follows its own setting.
            commandServer?.stop()
            commandServer = nil
            return
        }
        guard commandServer == nil else { return }
        guard let bundleIdentifier = Bundle.main.bundleIdentifier, let url = RemoteSocketPath.url(bundleIdentifier: bundleIdentifier) else {
            log.error("No place for the command line's socket")
            return
        }
        let server = AgentSocket.Server(url: url, handler: commandHandler)
        do {
            try server.start()
            commandServer = server
            log.notice("Answering the command line at \(url.path, privacy: .private)")
        } catch {
            log.error("The command line's socket didn't open: \(error.message, privacy: .public)")
            showError(String(localized: "The warble command couldn't start: \(error.message)"))
        }
    }

    /// Opens the socket other apps show activities over, or closes it, so while the setting is off no socket exists.
    private func listenForActivities(_ listen: Bool) {
        guard listen else {
            activitySocket?.stop()
            return
        }
        guard let socket = activitySocket, let handler = activityHandler, !socket.isListening else {
            if activitySocket == nil { log.error("No place for the activities socket") }
            return
        }
        do {
            try socket.start(handler: handler)
            log.notice("Showing activities from other apps, listening at \(socket.url.path, privacy: .private)")
        } catch {
            log.error("The activities socket didn't open: \(error.message, privacy: .public)")
            showError(String(localized: "Other apps can't show activities: \(error.message)"))
        }
    }

    /// Closes the sockets and removes them, as the settings turning off and quitting do.
    func stopListening() {
        commandServer?.stop()
        commandServer = nil
        activitySocket?.stop()
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
