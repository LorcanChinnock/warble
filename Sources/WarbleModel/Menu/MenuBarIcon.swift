import Foundation

/// Whether Warble's icon is in the menu bar. Settings › General can hide it, as can ⌘-dragging it off the bar, but it
/// comes back while an update waits, because its dot and menu are where Warble offers the update.
public enum MenuBarIcon {
    /// Stored as false once the icon is hidden. #258 removed an earlier setting stored as `showMenuBarIcon`, so this one
    /// has a new name, and a choice made before that can't hide the icon now.
    public static let shownKey = "menuBarIconShown"

    public static func isVisible(shown: Bool, updateWaiting: Bool) -> Bool {
        shown || updateWaiting
    }
}
