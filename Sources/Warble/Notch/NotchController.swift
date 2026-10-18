import AppKit
import os
import WarbleCore

private let log = Logger.warble("notch")

/// Puts the notch panel over the built-in display's camera housing in the current `state`, and moves or hides it when
/// displays change. It does no work between changes: no timers and no polling.
@MainActor
final class NotchController {
    var state = NotchState.hidden {
        didSet {
            if state != oldValue {
                update()
            }
        }
    }

    private let panel = NotchPanel()
    private var screenObserver: NSObjectProtocol?

    init() {
        // Posted when a display is plugged in or removed, its resolution changes, or the lid closes.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        // Only a built-in display has a notch; screens without one get a virtual notch later (#22).
        guard let notch = NSScreen.screens.lazy.compactMap(\.notch).first, let frame = NotchLayout.frame(state, notch: notch) else {
            panel.orderOut(nil)
            log.notice("Notch hidden (\(self.state.rawValue, privacy: .public))")
            return
        }
        panel.show(in: frame)
        log.notice("Notch \(self.state.rawValue, privacy: .public) at \(NSStringFromRect(frame), privacy: .public) over \(NSStringFromRect(notch), privacy: .public)")
    }
}
