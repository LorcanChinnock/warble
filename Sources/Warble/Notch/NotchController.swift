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
    /// What's playing, or `nil` to draw nothing. Nothing sets it until playback is read (#9), except the preview.
    var playback: PlaybackState? {
        didSet {
            model.playback = playback
            if playback == nil {
                // Start over, so a pointer still on the notch when playback returns is reported as entering again.
                hover = HoverIntent()
                pointerInside = false
                scheduleDeadline()
            }
            update()
        }
    }

    var state: NotchState {
        playback == nil ? .hidden : NotchState(hover.state)
    }

    private let model = NotchModel()
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
        // Posted when a display is plugged in or removed, its resolution changes, or the lid closes.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update(animated: false) }
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
            log.notice("Notch hidden (\(self.state.rawValue, privacy: .public))")
            return
        }
        listen(open: state == .peek || state == .expanded)
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
