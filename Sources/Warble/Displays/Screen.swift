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

    /// AppKit global frame of a pill-shaped camera cutout, or `nil` without one. macOS has no value for a cutout that
    /// we've confirmed, so a Mac with one reads as having no notch and gets the virtual notch, flush with the top edge.
    /// To see the pill, launch with `-notchPreviewHousing pill`, which gives the main display a made-up cutout.
    var cutout: CGRect? {
        guard UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["notchPreviewHousing"] as? String == "pill" else { return nil }
        return VirtualNotch.previewCutout(in: frame)
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
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        let ignoresNotch = arguments["notchPreviewVirtual"] != nil || arguments["notchPreviewHousing"] != nil
        return screens.enumerated().map { index, screen in
            NotchDisplay(
                id: screen.uuid, frame: screen.frame, menuBarHeight: screen.menuBarHeight,
                notch: ignoresNotch ? nil : screen.notch, cutout: screen.cutout, isMain: index == 0
            )
        }
    }

    static var underPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}
