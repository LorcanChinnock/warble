import AppKit
import SwiftUI
import WarbleCore

/// The black shape over the notch. It never takes the keyboard or the menu bar from the app in front.
final class NotchPanel: NSPanel {
    @MainActor
    init() {
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
    }

    /// Shows the shape filling `frame`. AppKit snaps a window to whole points, so over a notch with a half-point edge the
    /// window grows by up to a point at the bottom; the shape keeps to `frame`'s height from the top, and the rest stays
    /// clear, so the panel ends exactly where the camera housing does.
    func show(in frame: CGRect) {
        contentView = NSView(hosting: NotchView(height: frame.height))
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct NotchView: View {
    let height: CGFloat

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: Native.restingRadius, bottomTrailingRadius: Native.restingRadius)
            .fill(Native.panel)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .top)
            // Empty until the art and play-state bars arrive, so there's nothing to read yet.
            .accessibilityHidden(true)
    }
}
