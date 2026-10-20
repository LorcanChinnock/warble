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

    /// The display's UUID, which, unlike `displayID`, stays the same across launches and reconnections.
    var uuid: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return "\(displayID)" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Every display as the notch sees it; the first screen is the one with the menu bar.
    ///
    /// To see the virtual notch on a Mac with a notch, launch with `open build/WarbleDev.app --args -notchPreviewVirtual
    /// YES`, which treats every display as having none for that launch.
    static var notchDisplays: [NotchDisplay] {
        let ignoresNotch = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["notchPreviewVirtual"] != nil
        return screens.enumerated().map { index, screen in
            NotchDisplay(
                id: screen.uuid, frame: screen.frame, menuBarHeight: screen.menuBarHeight,
                notch: ignoresNotch ? nil : screen.notch, isMain: index == 0
            )
        }
    }

    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}
