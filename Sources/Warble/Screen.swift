import AppKit
import WarbleCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var menuBarHeight: CGFloat {
        MenuBar.height(screenFrame: frame, visibleFrame: visibleFrame, safeAreaTop: safeAreaInsets.top)
    }

    /// AppKit global frame of the camera housing, or `nil` without one.
    var notch: CGRect? {
        MenuBar.notch(safeAreaTop: safeAreaInsets.top, leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea)
    }

    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}
