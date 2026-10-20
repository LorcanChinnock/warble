import AppKit
import SwiftUI
import WarbleCore

/// The black shape over the notch. It never takes the keyboard or the menu bar from the app in front.
final class NotchPanel: NSPanel {
    /// Called with true when the pointer enters the area set by `track(_:)`, and false when it leaves.
    var onPointer: ((Bool) -> Void)?
    /// Called with each scroll over the panel, in any state.
    var onScroll: ((NSEvent) -> Void)?
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
        // Every Space, fixed in place while Spaces switch, and out of ⌘` cycling. No .fullScreenAuxiliary, so it stays
        // off a full-screen app's Space, where the menu bar and notch area belong to that app.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Built once, so a change of state animates instead of replacing the view.
        contentView = NSView(hosting: NotchView(model: model))
    }

    /// Fills `frame`, the larger of the shapes on screen. A window covers whole points, so over a notch with a half-point
    /// edge it grows outwards by up to a point; the shape keeps to its own height from the top and stays centred, and the
    /// rest stays clear, so the panel ends exactly where the camera housing does.
    func show(in frame: CGRect) {
        setFrame(NotchLayout.window(for: frame), display: true)
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
