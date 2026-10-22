import AppKit
import os
import SwiftUI
import WarbleCore

private let log = Logger.warble("notch")

/// Draws a notch over each camera housing, real or virtual, as `Store` decides, and moves, adds or removes them when
/// displays or their rules change. At rest it does no work: no timers, no polling and no event monitors.
@MainActor
final class NotchController {
    /// What's playing as the notch shows it, which `Store` keeps from what the sources report.
    var playback: PlaybackState? { store.state.playback }

    /// What the idle card shows before anything plays. The preview sets it instead of reading the saved one.
    var lastPlayed: LastPlayed? {
        get { player.lastPlayed }
        set { player.lastPlayed = newValue }
    }
    /// Where the last track played is kept across launches, or `nil` to keep it only in memory, as the preview does.
    private let lastPlayedStore: LastPlayedStore?
    /// The state last remembered, so a pause or a seek doesn't write to disk again.
    private var remembered: PlaybackState?
    /// Bumped by every track remembered, so one whose art finishes shrinking after the next has begun is dropped.
    private var remembers = 0
    /// The write in flight, which the next one waits for, so the file always ends up holding the latest track.
    private var saving: Task<Void, Never>?

    /// Sends a command to the app that's playing. Unset, as in the preview, a command only changes what the notch shows.
    var send: (PlaybackCommand) -> Void = { _ in }

    /// The checks behind the "!". `AppDelegate` tells it how the adapter is doing.
    let doctor: DoctorModel
    private let environment: AppEnvironment
    private var store: Store { environment.store }
    private let player = PlayerModel()
    private let volume = SystemVolume()
    private var followsVolume = false
    private let outputs = AudioOutputs()
    /// One for each housing, by `NotchDisplay.id`.
    private var surfaces: [String: NotchSurface] = [:]
    private var rules: [String: VirtualNotchRule] = [:]
    /// While the displays or their rules change, the notches move at once rather than morph.
    private var layingOut = false
    private var clickMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    init(lastPlayedStore: LastPlayedStore?, environment: AppEnvironment) {
        self.lastPlayedStore = lastPlayedStore
        self.environment = environment
        doctor = DoctorModel(updater: environment.updater)
        store.onChange = { [weak self] old, new, action in self?.stateChanged(from: old, to: new, by: action) }
        environment.runner.platform = { [weak self] in self?.perform($0) }
        player.onCommand = { [weak self] in self?.perform($0) }
        player.onOpenApp = { [weak self] in self?.openApp() }
        player.onVolume = { [weak self] in self?.setVolume($0) }
        player.onSelectOutput = { [weak self] in self?.selectOutput($0) }
        doctor.onChange = { [weak self] in
            guard let self else { return }
            self.store.dispatch(.attentionChanged(self.doctor.needsAttention))
        }
        environment.displays.onChange = { [weak self] in self?.layOut() }
        // Any write to Warble's defaults; only a change of rule lays the notches out again.
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let preferences = Preferences()
                let state = self.store.state
                if preferences.stayVisibleAfterPausing != state.idle.delay {
                    self.store.dispatch(.stayVisibleChanged(preferences.stayVisibleAfterPausing))
                }
                if preferences.idleHover != state.idleHover {
                    self.store.dispatch(.idleHoverChanged(preferences.idleHover))
                }
                if preferences.trackChangeToast != state.showsTrackToast {
                    self.store.dispatch(.trackToastChanged(preferences.trackChangeToast))
                }
                if preferences.virtualNotchRules != self.rules {
                    self.layOut()
                }
            }
        })
        layOut()
        loadLastPlayed()
    }

    /// Reads the track saved last time, unless one has played since Warble opened.
    private func loadLastPlayed() {
        guard let store = lastPlayedStore else { return }
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { store.load() }.value
            guard let self, self.remembered == nil, let saved else { return }
            self.player.lastPlayed = saved
        }
    }

    /// Keeps `state` as the last track played, with a small copy of its art, and saves it for the next launch. Only a
    /// new track or new art does any work.
    private func remember(_ state: PlaybackState) {
        guard LastPlayed.changes(from: remembered, to: state) else { return }
        remembered = state
        remembers += 1
        let pass = remembers
        let appName = player.appName
        Task { [weak self] in
            let lastPlayed = await Task.detached(priority: .utility) { LastPlayedStore.remembering(state, appName: appName) }.value
            guard let self, pass == self.remembers else { return }
            self.player.lastPlayed = lastPlayed
            guard let store = self.lastPlayedStore else { return }
            let previous = self.saving
            self.saving = Task.detached(priority: .utility) {
                await previous?.value
                do {
                    try store.save(lastPlayed)
                } catch {
                    log.error("Couldn't save the last track played: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Puts a surface over each housing the displays and their rules call for, moving the ones that stay and removing
    /// the rest at once.
    private func layOut() {
        rules = Preferences().virtualNotchRules
        let housings = environment.displays.housings(rules: rules)
        let kept = Set(housings.map(\.display))
        for (display, surface) in surfaces where !kept.contains(display) {
            surface.remove()
            surfaces[display] = nil
        }
        for housing in housings {
            let surface = surfaces[housing.display] ?? makeSurface(housing)
            surfaces[housing.display] = surface
            surface.housing = housing.frame
        }
        layingOut = true
        store.dispatch(.housingsChanged(housings))
        layingOut = false
        log.notice("Notches over \(housings.map { NSStringFromRect($0.frame) }.joined(separator: ", "), privacy: .public)")
    }

    private func makeSurface(_ housing: NotchHousing) -> NotchSurface {
        let store = store
        let surface = NotchSurface(
            display: housing.display, housing: housing.frame, player: player, doctor: doctor, settings: environment.settings,
            dispatch: { [weak store] in store?.dispatch($0) }
        ) { [weak self] in self?.scroll($0) }
        surface.onKey = { [weak self] event in self?.key(event) ?? false }
        surface.makeMenu = { [weak self] in
            guard let self else { return nil }
            return NotchMenu.make(source: self.playback?.bundleIdentifier ?? self.player.lastPlayed?.bundleIdentifier, updater: self.environment.updater, settingsWindow: self.environment.settingsWindow) { [weak self] in
                self?.openApp()
            }
        }
        return surface
    }

    /// Draws what `Store` decided: the track, the last one played, and each notch's state.
    private func stateChanged(from old: AppState, to new: AppState, by action: AppAction) {
        if new.playback != old.playback {
            player.playback = new.playback
            if let playback = new.playback {
                remember(playback)
            }
        }
        if new.showsPlayback != old.showsPlayback {
            log.notice("Playback \(new.showsPlayback ? "shown" : "idle", privacy: .public)")
        }
        for (display, surface) in surfaces {
            surface.apply(new)
            surface.update(animated: !layingOut)
            guard old.notchState(display) != .expanded, new.notchState(display) == .expanded else { continue }
            switch action {
            case .hover(_, .click):
                surface.measureExpand(cause: "click", since: Perf.input?.timestamp)
            case .hover(_, .keyboard):
                surface.measureExpand(cause: "shortcut", since: nil)
            case .tick:
                // From when the hover delay ended, so a timer that fires late counts against the budget too.
                let due = store.tickDeadline.map { ProcessInfo.processInfo.systemUptime + $0.timeIntervalSinceNow }
                surface.measureExpand(cause: "hover", since: due)
            default:
                break
            }
        }
    }

    /// Carries out the effects that need AppKit.
    private func perform(_ effect: AppEffect) {
        switch effect {
        case .watchClicksOutside(let watch):
            watchClicksOutside(watch)
        case .followVolume(let follow):
            followVolume(follow)
        case .notchOpened:
            // Opening a notch checks again whatever the Doctor found, in case the user fixed it, such as in System
            // Settings, which tells Warble nothing.
            if doctor.adapter != .working {
                doctor.refresh()
            }
        case .takeEscape:
            break
        }
    }

    /// Opens the notch on the display the pointer is on, or else the built-in one, with the keyboard in it, or closes it
    /// again. Any other notch that's open closes, as for a click.
    func toggleKeyboard() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
        let onScreen = surfaces.values.first { surface in screen.map { $0.frame.intersects(surface.housing) } ?? false }
        guard let surface = onScreen ?? surfaces.values.first(where: { !$0.isVirtual }) ?? surfaces.values.first else { return }
        let handback = surfaces.values.lazy.filter { $0 !== surface }.compactMap { $0.takeKeyboardHandback() }.first
        surface.toggleKeyboard(handback: handback)
    }

    /// Does what a key means while a notch has the keyboard (`NotchKey`), and says whether it meant anything.
    private func key(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), eventFlags: CGEventFlags(rawValue: UInt64(flags.rawValue)))
        guard let key = NotchKey(keyCode: combo.keyCode, modifiers: combo.modifiers) else { return false }
        switch key {
        case .command(let command):
            perform(command)
        case .seek(let delta):
            if let playback, let position = NotchKey.position(seeking: delta, in: playback, at: .now) {
                perform(.seek(to: position))
            }
        case .volume(let delta):
            if let current = volume.volume {
                setVolume(NotchKey.volume(changing: volume.isMuted ? 0 : current, by: delta))
            }
        case .close:
            store.dispatch(.dismiss(except: nil))
        }
        return true
    }

    /// Shows what a command will do before the app reports back, so a click on play/pause answers at once. Skipping waits
    /// for the app, since only it knows the next track. The app's next report replaces the guess either way. While a hide
    /// is pending there's no guess, since setting one would cancel the hide and keep a stopped track on screen.
    func perform(_ command: PlaybackCommand) {
        if store.state.hideAt == nil, let current = playback {
            var guess = current
            switch command {
            case .play: guess = current.playing(true, at: .now)
            case .pause: guess = current.playing(false, at: .now)
            case .togglePlayPause: guess = current.playing(!current.isPlaying, at: .now)
            case .seek(let position): guess = current.seeked(to: position, at: .now)
            case .setShuffle(let mode): guess.shuffle = mode
            case .setRepeat(let mode): guess.repeatMode = mode
            case .nextTrack, .previousTrack: break
            }
            if guess != current {
                store.dispatch(.playbackReported(guess))
            }
            if command == .togglePlayPause || command == .play || command == .pause {
                // The click's own window is the notch it was on; a shortcut has none.
                let input = Perf.input
                Perf.untilNextFrame("Play/pause", on: NSApp.currentEvent?.window?.screen ?? NSScreen.main, cause: input?.cause ?? "shortcut", since: input?.timestamp)
            }
        }
        send(command)
    }

    /// Brings the app that's playing to the front, or while Idle the one that played last, opening it if it's quit.
    private func openApp() {
        guard let bundleIdentifier = playback?.bundleIdentifier ?? player.lastPlayed?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Scrolling over the notch changes the volume, with a light tick on a Force Touch trackpad at each tenth.
    private func scroll(_ event: NSEvent) {
        guard let current = volume.volume, event.scrollingDeltaY != 0 else { return }
        let from = volume.isMuted ? 0 : current
        let to = VolumeScroll.volume(
            after: event.scrollingDeltaY, from: from,
            precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice
        )
        guard to != from else { return }
        setVolume(to)
        if VolumeScroll.crossesTick(from: from, to: to) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    private func setVolume(_ value: Double) {
        volume.set(value)
        readVolume()
    }

    private func readVolume() {
        player.volume = volume.volume
        player.isMuted = volume.isMuted
    }

    /// Reads the volume and the outputs, and follows changes from the volume keys and elsewhere, only while the slider
    /// shows.
    private func followVolume(_ follow: Bool) {
        guard follow != followsVolume else { return }
        followsVolume = follow
        if follow {
            readVolume()
            readOutputs()
            volume.startListening { [weak self] in self?.readVolume() }
            outputs.startListening { [weak self] in self?.readOutputs() }
        } else {
            volume.stopListening()
            outputs.stopListening()
        }
    }

    private func readOutputs() {
        player.outputs = outputs.all
        player.currentOutput = outputs.current
    }

    /// `SystemVolume` moves to the new output, and its listener reads the new output's volume.
    private func selectOutput(_ id: UInt32) {
        outputs.select(id)
        readOutputs()
    }

    /// Clicks in other apps close the open notches; a click on the panel itself is the panel's own.
    private func watchClicksOutside(_ watch: Bool) {
        if watch, clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.dispatch(.dismiss(except: nil)) }
            }
        } else if !watch, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
