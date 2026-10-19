import AppKit
import Carbon.HIToolbox
import os
import SwiftUI
import WarbleCore

private let log = Logger.warble("notch")

/// Puts the notch panel over the built-in display's camera housing, opens it as `HoverIntent` decides, and moves or hides
/// it when displays change. At rest it does no work: no timers, no polling and no event monitors.
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
            model.playback = shownPlayback
            if shownPlayback == nil {
                // Start over, so a pointer still on the notch when playback returns is reported as entering again.
                hover = HoverIntent()
                pointerInside = false
                scheduleDeadline()
            }
            update()
        }
    }

    /// Sends a command to the app that's playing. Unset, as in the preview, a command only changes what the notch shows.
    var send: (PlaybackCommand) -> Void = { _ in }

    var state: NotchState {
        playback == nil ? .hidden : NotchState(hover.state)
    }

    private let model = NotchModel()
    private let volume = SystemVolume()
    private var followsVolume = false
    private let panel: NotchPanel
    private var hover = HoverIntent()
    private var deadlineTimer: Timer?
    /// The state and frame last shown, and the frame the panel has, which stays the larger one until a morph ends.
    private var shown: (state: NotchState, frame: CGRect)?
    private var panelFrame: CGRect?
    /// Bumped by every change, so a morph that ends after another has begun doesn't shrink the panel under it.
    private var morphs = 0
    private var pointerInside = false
    private var clickMonitor: Any?
    private var takesEscape = false
    private var screenObserver: NSObjectProtocol?

    init() {
        panel = NotchPanel(model: model)
        panel.onPointer = { [weak self] inside in self?.pointer(inside: inside) }
        model.onClick = { [weak self] in self?.handle(.click) }
        model.onCommand = { [weak self] in self?.perform($0) }
        model.onOpenApp = { [weak self] in self?.openApp() }
        model.onVolume = { [weak self] in self?.setVolume($0) }
        panel.onScroll = { [weak self] in self?.scroll($0) }
        // Posted when a display is plugged in or removed, its resolution changes, or the lid closes.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(animated: false) }
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
        model.volume = volume.volume
        model.isMuted = volume.isMuted
    }

    /// Reads the volume, and follows changes from the volume keys and elsewhere, only while the slider shows.
    private func followVolume(_ follow: Bool) {
        guard follow != followsVolume else { return }
        followsVolume = follow
        if follow {
            readVolume()
            volume.startListening { [weak self] in self?.readVolume() }
        } else {
            volume.stopListening()
        }
    }

    private func pointer(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        handle(inside ? .pointerEntered : .pointerLeft)
    }

    private func handle(_ event: HoverEvent) {
        hover.handle(event, at: .now)
        scheduleDeadline()
        update()
    }

    /// One timer at most, for `HoverIntent`'s next deadline, and none while nothing is due.
    private func scheduleDeadline() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard let deadline = hover.deadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hover.advance(to: max(.now, deadline))
                self.scheduleDeadline()
                self.update()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        deadlineTimer = timer
    }

    private func update(animated: Bool = true) {
        let state = state
        // Only a built-in display has a notch; screens without one get a virtual notch later (#22).
        guard let notch = NSScreen.screens.lazy.compactMap(\.notch).first, let frame = NotchLayout.frame(state, notch: notch) else {
            morphs += 1
            panel.orderOut(nil)
            shown = nil
            panelFrame = nil
            model.state = .hidden
            listen(open: false)
            followVolume(false)
            log.notice("Notch hidden (\(self.state.rawValue, privacy: .public))")
            return
        }
        listen(open: state == .peek || state == .expanded)
        followVolume(state == .expanded)
        guard shown?.state != state || shown?.frame != frame else { return }
        let previous = shown
        shown = (state, frame)
        morphs += 1
        let morph = morphs
        model.notch = notch
        if animated, let previous, let panelFrame, previous.frame != frame {
            // Grow the panel before the shape does, so nothing is clipped, and shrink it once the shape has.
            let union = panelFrame.union(frame)
            if union != panelFrame {
                show(in: union)
            }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduceMotion ? Native.fade : Native.morph, completionCriteria: .removed) {
                model.state = state
            } completion: { [weak self] in
                guard let self, morph == self.morphs, self.panelFrame != frame else { return }
                self.show(in: frame)
            }
        } else {
            model.state = state
            show(in: frame)
        }
        panel.track(NotchLayout.hoverArea(state, notch: notch) ?? .zero)
        log.notice("Notch \(state.rawValue, privacy: .public) at \(NSStringFromRect(frame), privacy: .public) over \(NSStringFromRect(notch), privacy: .public)")
    }

    private func show(in frame: CGRect) {
        panelFrame = frame
        panel.show(in: frame)
    }

    /// While the notch is open, a click anywhere else closes it, and so does Escape with the pointer on it. Both stop at
    /// rest, so a resting notch watches nothing and never takes Escape from the app in front.
    private func listen(open: Bool) {
        if open, clickMonitor == nil {
            // Clicks in other apps; a click on the panel itself is the panel's own.
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.dismiss) }
            }
        } else if !open, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        let wantsEscape = open && pointerInside
        if wantsEscape, !takesEscape {
            takesEscape = HotkeyCenter.shared.registerTemporary(KeyCombo(keyCode: UInt32(kVK_Escape), modifiers: 0)) { [weak self] in
                self?.handle(.dismiss)
            }
        } else if !wantsEscape, takesEscape {
            HotkeyCenter.shared.unregisterTemporary()
            takesEscape = false
        }
    }
}
