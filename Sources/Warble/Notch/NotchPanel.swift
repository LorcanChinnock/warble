import AppKit
import SwiftUI
import WarbleCore

/// The black shape over the notch. It never takes the keyboard or the menu bar from the app in front.
final class NotchPanel: NSPanel {
    /// Called with true when the pointer enters the area set by `track(_:)`, and false when it leaves.
    var onPointer: ((Bool) -> Void)?
    /// Called with each scroll over the panel, in any state.
    var onScroll: ((NSEvent) -> Void)?
    /// Called with a right-click or Control-click on the panel, in any state, instead of the click reaching the content.
    var onMenu: ((NSEvent) -> Void)?
    /// Called when the window server moves the panel, as it can while it rebuilds the displays.
    var onDisplaced: (() -> Void)?
    private var hoverArea = CGRect.zero
    private var trackingArea: NSTrackingArea?

    @MainActor
    init(model: NotchModel) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Above the menu bar and its status items, which the wings partly cover, as Shot's recording pill sits. Higher
        // levels, such as boring.notch's .mainMenu + 3, would also cover pop-up menus that open under the menu bar.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        // Every Space, fixed in place while Spaces switch, and out of ⌘` cycling. A panel like this one joins a full-screen
        // app's Space whatever it asks for, so it joins them all alike, and the store hides the notch over a full-screen app.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Set rather than left to its default, under which a window lets the pointer through where it draws nothing, so
        // an Idle virtual notch, drawn clear, still reports a hover.
        ignoresMouseEvents = false
        // Built once, so a change of state animates instead of replacing the view.
        contentView = NSView(hosting: NotchView(model: model))
        // The window server fits windows to each half-built arrangement while displays change, and nothing else moves this one.
        for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onDisplaced?() }
            }
        }
    }

    /// Fills `frame`, the larger of the shapes on screen. A window covers whole points, so over a notch with a half-point
    /// edge it grows outwards by up to a point; the shape keeps to its own height from the top and stays centred, and the
    /// rest stays clear, so the panel ends exactly where the camera housing does.
    func show(in frame: CGRect) {
        setFrame(NotchLayout.window(for: frame), display: false)
        // Lay the content out at the new size now, before a morph begins, so the shape stays centred over the housing.
        // Otherwise SwiftUI takes the new size in the same pass as the morph, and the shape slides over from the window's
        // old left edge as it grows.
        contentView?.layoutSubtreeIfNeeded()
        displayIfNeeded()
        orderFrontRegardless()
        retrack()
    }

    /// Reports the pointer entering and leaving `area`, in AppKit screen space, through `onPointer`.
    func track(_ area: CGRect) {
        hoverArea = area
        retrack()
    }

    /// Reports whether the pointer is in the tracked area now, for when AppKit may have missed it crossing.
    func recheckPointer() {
        onPointer?(hoverArea.contains(NSEvent.mouseLocation))
    }

    /// A tracking area is in window space, so it moves with every change of frame or area. A pointer already inside the
    /// new area is reported at once, since AppKit only reports crossings.
    private func retrack() {
        guard let view = contentView else { return }
        if let trackingArea {
            view.removeTrackingArea(trackingArea)
        }
        let inside = hoverArea.contains(NSEvent.mouseLocation)
        let options: NSTrackingArea.Options = inside ? [.mouseEnteredAndExited, .activeAlways, .assumeInside] : [.mouseEnteredAndExited, .activeAlways]
        let area = NSTrackingArea(rect: convertFromScreen(hoverArea), options: options, owner: self)
        view.addTrackingArea(area)
        trackingArea = area
        onPointer?(inside)
    }

    override func mouseEntered(with event: NSEvent) { onPointer?(true) }
    override func mouseExited(with event: NSEvent) { onPointer?(false) }
    override func scrollWheel(with event: NSEvent) { onScroll?(event) }

    /// Takes a right-click, or a Control-click, before SwiftUI does, so it never reaches the controls or counts as a click
    /// that opens the notch.
    override func sendEvent(_ event: NSEvent) {
        let isMenuClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control))
        if isMenuClick, let onMenu {
            onMenu(event)
        } else {
            super.sendEvent(event)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
