import AppKit
import Carbon.HIToolbox
import os
import SwiftUI
import WarbleCore

private let log = Logger.warble("notch")

/// Draws a notch over each camera housing, real or virtual, opens each as its `HoverIntent` decides, and moves, adds or
/// removes them when displays or their rules change. At rest it does no work: no timers, no polling and no event monitors.
@MainActor
final class NotchController {
    /// What's playing, or `nil` to draw nothing. `AdapterSource` sets it, or the preview track at launch.
    ///
    /// A source reports nothing for a moment while it changes track, so `nil` hides the notch only if nothing follows
    /// within `hideDelay`; otherwise a skip would close the notch under the pointer.
    var playback: PlaybackState? {
        get { shownPlayback }
        set {
            hideTimer?.invalidate()
            hideTimer = nil
            guard newValue == nil, shownPlayback != nil else {
                shownPlayback = newValue
                return
            }
            hideTimer = Timer.scheduledTimer(withTimeInterval: Self.hideDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.shownPlayback = nil }
            }
        }
    }

    /// Longer than the gap the adapter leaves between tracks, about half a second.
    private static let hideDelay: TimeInterval = 1.5
    private var hideTimer: Timer?

    private var shownPlayback: PlaybackState? {
        didSet {
            player.playback = shownPlayback
            guard (shownPlayback == nil) != (oldValue == nil) else { return }
            for surface in surfaces.values {
                surface.isPlaying = shownPlayback != nil
                surface.update()
            }
            changed()
        }
    }

    /// Sends a command to the app that's playing. Unset, as in the preview, a command only changes what the notch shows.
    var send: (PlaybackCommand) -> Void = { _ in }

    private let player = PlayerModel()
    private let volume = SystemVolume()
    private var followsVolume = false
    private let outputs = AudioOutputs()
    /// One for each housing, by `NotchDisplay.id`.
    private var surfaces: [String: NotchSurface] = [:]
    private var rules: [String: VirtualNotchRule] = [:]
    private var clickMonitor: Any?
    private var takesEscape = false
    private var observers: [NSObjectProtocol] = []

    init() {
        player.onCommand = { [weak self] in self?.perform($0) }
        player.onOpenApp = { [weak self] in self?.openApp() }
        player.onVolume = { [weak self] in self?.setVolume($0) }
        player.onSelectOutput = { [weak self] in self?.selectOutput($0) }
        // Posted when a display is plugged in or removed, its resolution changes, or the lid closes.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layOut() }
        })
        // Any write to Warble's defaults; only a change of rule lays the notches out again.
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Preferences().virtualNotchRules != self.rules else { return }
                self.layOut()
            }
        })
        layOut()
    }

    /// Puts a surface over each housing the displays and their rules call for, moving the ones that stay and removing
    /// the rest at once.
    private func layOut() {
        rules = Preferences().virtualNotchRules
        let housings = VirtualNotch.housings(NSScreen.notchDisplays, rules: rules)
        let kept = Set(housings.map(\.display))
        for (display, surface) in surfaces where !kept.contains(display) {
            surface.remove()
            surfaces[display] = nil
        }
        for housing in housings {
            let surface = surfaces[housing.display] ?? makeSurface(over: housing.frame)
            surfaces[housing.display] = surface
            surface.housing = housing.frame
            surface.isPlaying = shownPlayback != nil
            surface.update(animated: false)
        }
        log.notice("Notches over \(housings.map { NSStringFromRect($0.frame) }.joined(separator: ", "), privacy: .public)")
        changed()
    }

    private func makeSurface(over housing: CGRect) -> NotchSurface {
        let surface = NotchSurface(housing: housing, player: player) { [weak self] in self?.scroll($0) }
        surface.onChange = { [weak self] in self?.changed() }
        // A click on one notch closes any other that's open; clicks in other apps are the click monitor's.
        surface.onClick = { [weak self, weak surface] in
            self?.dismiss { $0 !== surface }
        }
        return surface
    }

    /// Listens for clicks elsewhere and Escape, and follows the volume, only while a notch is open.
    private func changed() {
        let open = surfaces.values.contains { $0.state == .expanded }
        listen(open: open, pointerInside: surfaces.values.contains { $0.state == .expanded && $0.pointerInside })
        followVolume(open)
    }

    private func dismiss(where included: (NotchSurface) -> Bool = { _ in true }) {
        for surface in surfaces.values where surface.state == .expanded && included(surface) {
            surface.handle(.dismiss)
        }
    }

    /// Shows what a command will do before the app reports back, so a click on play/pause answers at once. Skipping waits
    /// for the app, since only it knows the next track. The app's next report replaces the guess either way. While a hide
    /// is pending there's no guess, since setting one would cancel the hide and keep a stopped track on screen.
    private func perform(_ command: PlaybackCommand) {
        if hideTimer == nil, let current = playback {
            switch command {
            case .play: playback = current.playing(true, at: .now)
            case .pause: playback = current.playing(false, at: .now)
            case .togglePlayPause: playback = current.playing(!current.isPlaying, at: .now)
            case .seek(let position): playback = current.seeked(to: position, at: .now)
            case .setShuffle(let mode): playback?.shuffle = mode
            case .setRepeat(let mode): playback?.repeatMode = mode
            case .nextTrack, .previousTrack: break
            }
        }
        send(command)
    }

    private func openApp() {
        guard let bundleIdentifier = playback?.bundleIdentifier,
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

    /// While a notch is open, a click anywhere else closes it, and so does Escape with the pointer on it. Both stop at
    /// rest, so a resting notch watches nothing and never takes Escape from the app in front.
    private func listen(open: Bool, pointerInside: Bool) {
        if open, clickMonitor == nil {
            // Clicks in other apps; a click on the panel itself is the panel's own.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        } else if !open, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        let wantsEscape = open && pointerInside
        if wantsEscape, !takesEscape {
            takesEscape = HotkeyCenter.shared.registerTemporary(KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0)) { [weak self] in
                self?.dismiss()
            }
        } else if !wantsEscape, takesEscape {
            HotkeyCenter.shared.unregisterTemporary()
            takesEscape = false
        }
    }
}
