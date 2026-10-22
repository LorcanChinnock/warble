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

    private let environment: AppEnvironment
    private var store: Store { environment.store }
    private let player: PlayerModel
    private var doctor: DoctorModel { environment.doctor }
    private var volume: SystemVolume { environment.volume }
    /// One for each housing, by `NotchDisplay.id`.
    private var surfaces: [String: NotchSurface] = [:]
    private var rules: [String: VirtualNotchRule] = [:]
    /// While the displays or their rules change, the notches move at once rather than morph.
    private var layingOut = false
    private var observers: [NSObjectProtocol] = []

    init(environment: AppEnvironment) {
        self.environment = environment
        let store = environment.store
        player = PlayerModel { [weak store] in store?.dispatch($0) }
        store.onChange = { [weak self] old, new, action in self?.stateChanged(from: old, to: new, by: action) }
        environment.platform.toggleKeyboard = { [weak self] in self?.toggleKeyboard() }
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
                if preferences.toastsInFullScreen != state.toastsInFullScreen {
                    self.store.dispatch(.toastsInFullScreenChanged(preferences.toastsInFullScreen))
                }
                if preferences.lyrics != state.lyrics.isOn {
                    self.store.dispatch(.lyricsChanged(preferences.lyrics))
                }
                if preferences.swipeToSkip != state.swipeToSkip {
                    self.store.dispatch(.swipeToSkipChanged(preferences.swipeToSkip))
                }
                if preferences.podcastSkips != state.podcastSkips {
                    self.store.dispatch(.podcastSkipsChanged(preferences.podcastSkips))
                }
                if preferences.dragArtOut != state.dragArtOut {
                    self.store.dispatch(.dragArtOutChanged(preferences.dragArtOut))
                }
                if preferences.virtualNotchRules != self.rules {
                    self.layOut()
                }
            }
        })
        // Going full screen, or back, switches Space; only then can a display start or stop showing a full-screen app.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readFullScreen() }
        })
        layOut()
    }

    private func readFullScreen() {
        let displays = FullScreenSpaces.displays()
        if displays != store.state.fullScreen {
            log.notice("Full screen on \(displays.count, privacy: .public) displays")
            store.dispatch(.fullScreenChanged(displays))
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
        readFullScreen()
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
                self?.store.dispatch(.openApp)
            }
        }
        return surface
    }

    /// Draws what `Store` decided: the track, the last one played, the volume and outputs, the Doctor's checks, and each
    /// notch's state.
    private func stateChanged(from old: AppState, to new: AppState, by action: AppAction) {
        if new.playback != old.playback {
            player.playback = new.playback
        }
        if new.lastPlayed != old.lastPlayed {
            player.lastPlayed = new.lastPlayed
        }
        if new.volume != old.volume || new.isMuted != old.isMuted {
            player.volume = new.volume
            player.isMuted = new.isMuted
        }
        if new.outputs != old.outputs || new.currentOutput != old.currentOutput {
            player.outputs = new.outputs
            player.currentOutput = new.currentOutput
        }
        if new.doctor.adapter != old.doctor.adapter {
            log.notice("Adapter is \(String(describing: new.doctor.adapter), privacy: .public)")
        }
        doctor.apply(new.doctor)
        if isPlayPause(action), old.hideAt == nil, old.playback != nil {
            // Timed from the click or key to the first frame that shows the new state. The click's own window is the
            // notch it was on; a shortcut has none.
            let input = Perf.input
            Perf.untilNextFrame("Play/pause", on: NSApp.currentEvent?.window?.screen ?? NSScreen.main, cause: input?.cause ?? "shortcut", since: input?.timestamp)
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

    private func isPlayPause(_ action: AppAction) -> Bool {
        switch action {
        case .command(.togglePlayPause), .command(.play), .command(.pause), .perform(.playPause): true
        default: false
        }
    }

    /// Opens the notch on the display the pointer is on, or else the built-in one, with the keyboard in it, or closes it
    /// again. Any other notch that's open closes, as for a click.
    private func toggleKeyboard() {
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
            store.dispatch(.command(command))
        case .seek(let delta):
            if let playback, let position = NotchKey.position(seeking: delta, in: playback, at: .now) {
                store.dispatch(.command(.seek(to: position)))
            }
        case .volume(let delta):
            store.dispatch(.volumeKey(delta: delta, volume: volume.volume, isMuted: volume.isMuted))
        case .close:
            store.dispatch(.dismiss(except: nil))
        }
        return true
    }

    /// Scrolling over a notch changes the volume, from the volume now, since the card with the slider may not be open, and
    /// a sideways swipe can skip.
    private func scroll(_ event: NSEvent) {
        store.dispatch(.scrolled(
            delta: event.scrollingDeltaY, across: event.scrollingDeltaX, phase: Self.phase(of: event),
            precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice,
            volume: volume.volume, isMuted: volume.isMuted
        ))
    }

    /// Where a scroll falls in its trackpad gesture, or `nil` for a mouse wheel, which has no gesture.
    private static func phase(of event: NSEvent) -> Swipe.Phase? {
        if !event.phase.isDisjoint(with: [.mayBegin, .began]) { return .began }
        if event.phase.contains(.changed) || event.phase.contains(.stationary) { return .changed }
        if !event.phase.isDisjoint(with: [.ended, .cancelled]) { return .ended }
        return event.momentumPhase.isEmpty ? nil : .momentum
    }
}
