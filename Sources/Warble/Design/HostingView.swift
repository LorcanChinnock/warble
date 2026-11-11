import AppKit
import SwiftUI

extension NSView {
    /// A window's content view hosting SwiftUI one level down. A hosting view that is itself the content view resizes the
    /// window and sets its size limits from inside AppKit's layout pass, which throws once content changes under a visible window.
    convenience init(hosting rootView: some View) {
        self.init()
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    /// The height `rootView` takes at `width`, measured off screen, for a window that fits its content before it shows.
    static func fittingHeight(of rootView: some View, width: CGFloat) -> CGFloat {
        let hosting = NSHostingView(rootView: rootView.frame(width: width))
        return hosting.fittingSize.height.rounded(.up)
    }
}
