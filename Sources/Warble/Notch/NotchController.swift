import AppKit
import os
import SwiftUI
import WarbleCore

private let log = Logger.warble("notch")

/// Draws a notch over each camera housing, real or virtual, as `Store` decides, and moves, adds or removes them when
/// displays change. At rest it does no work: no timers, no polling and no event monitors.
@MainActor
final class NotchController {
    /// What's playing as the notch shows it, which `Store` keeps from what the sources report.
    var playback: PlaybackState? { store.state.playback }

    private let environment: AppEnvironment
    private var store: Store { environment.store }
    private let player: PlayerModel
    private var volume: SystemVolume { environment.volume }
    private var gesture = ScrollGesture()
    private var heldVolume = HeldVolume()
    /// One for each housing, by `NotchDisplay.id`.
    private var surfaces: [String: NotchSurface] = [:]
    /// While the displays change, the notches move at once rather than morph.
    private var layingOut = false
    private var observers: [NSObjectProtocol] = []

    init(environment: AppEnvironment) {
        self.environment = environment
        let store = environment.store
        player = PlayerModel { [weak store] in store?.dispatch($0) }
        player.showsGlow = store.state.showsGlow
        store.onChange = { [weak self] old, new, action in self?.stateChanged(from: old, to: new, by: action) }
        environment.displays.onChange = { [weak self] in self?.layOut() }
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

    /// Puts a surface over each housing the displays call for, moving the ones that stay and removing
    /// the rest at once.
    private func layOut() {
        let housings = environment.displays.housings
        let kept = Set(housings.map(\.display))
        for (display, surface) in surfaces where !kept.contains(display) {
            surface.remove()
            surfaces[display] = nil
        }
        for housing in housings {
            let surface = surfaces[housing.display] ?? makeSurface(housing)
            surfaces[housing.display] = surface
            surface.housing = housing.frame
            surface.replace()
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
            display: housing.display, housing: housing.frame, player: player,
            dispatch: { [weak store] in store?.dispatch($0) }
        ) { [weak self] in self?.scroll($0) }
        surface.makeMenu = { [weak self] in
            guard let self else { return nil }
            return NotchMenu.make(source: self.playback?.bundleIdentifier, updater: self.environment.updater, settingsWindow: self.environment.settingsWindow) { [weak self] in
                self?.store.dispatch(.openApp)
            }
        }
        return surface
    }

    /// Draws what `Store` decided: the track, the volume and outputs, and each
    /// notch's state.
    private func stateChanged(from old: AppState, to new: AppState, by action: AppAction) {
        if new.playback != old.playback {
            player.playback = new.playback
        }
        if new.showsGlow != old.showsGlow {
            player.showsGlow = new.showsGlow
        }
        if new.volume != old.volume || new.isMuted != old.isMuted {
            player.volume = new.volume
            player.isMuted = new.isMuted
        }
        if new.outputs != old.outputs || new.currentOutput != old.currentOutput {
            player.outputs = new.outputs
            player.currentOutput = new.currentOutput
        }
        if new.outputSwitch != old.outputSwitch || new.outputs != old.outputs {
            player.keptOutput = new.outputSwitch.kept.flatMap { kept in new.outputs.first { $0.id == kept }?.name }
        }
        if isPlayPause(action), old.hideAt == nil, old.playback != nil {
            // Timed from the click or key to the first frame that shows the new state.
            let input = Perf.input
            Perf.untilNextFrame("Play/pause", on: NSApp.currentEvent?.window?.screen ?? NSScreen.main, cause: input?.cause ?? "shortcut", since: input?.timestamp)
        }
        if new.showsPlayback != old.showsPlayback {
            log.notice("Playback \(new.showsPlayback ? "shown" : "idle", privacy: .public)")
        }
        for (display, surface) in surfaces {
            surface.render(new, animated: !layingOut)
            guard old.notchState(display) != .expanded, new.notchState(display) == .expanded else { continue }
            switch action {
            case .hover(_, .click):
                surface.measureExpand(cause: "click", since: Perf.input?.timestamp)
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
        case .command(.togglePlayPause), .command(.play), .command(.pause): true
        default: false
        }
    }

    /// Scrolling over a notch changes the volume, slides through the song or, in a quick flick, skips. The volume is read
    /// from the volume now, since the card with the slider may not be open, and then followed here while the scroll
    /// lasts, since a device can report an old volume just after it was set.
    private func scroll(_ event: NSEvent) {
        let phase: ScrollGesture.Phase = if !event.momentumPhase.isEmpty {
            .momentum
        } else if event.phase.contains(.began) {
            .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            .ended
        } else {
            .changed
        }
        let inverted = event.isDirectionInvertedFromDevice
        let precise = event.hasPreciseScrollingDeltas
        switch gesture.handle(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, precise: precise, inverted: inverted, phase: phase, at: event.timestamp) {
        case .volume(let delta)?:
            let isMuted = volume.isMuted
            let current = heldVolume.start(delta: delta, device: { volume.volume }, isMuted: isMuted, precise: precise, inverted: inverted, at: event.timestamp)
            store.dispatch(.scrolled(delta: delta, precise: precise, inverted: inverted, volume: current, isMuted: isMuted))
        case .scrub(let seconds)?:
            store.dispatch(.scrubbed(by: seconds))
        case .skip(let next)?:
            store.dispatch(.flicked(next: next))
        default:
            break
        }
    }
}
