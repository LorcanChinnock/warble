/// Which clicks on the notch open its menu instead of reaching the controls.
public enum NotchClick {
    /// A right-click, or a Control-click with the left button, as macOS treats it.
    public static func opensMenu(isRightButtonDown: Bool, isLeftButtonDown: Bool, control: Bool) -> Bool {
        isRightButtonDown || (isLeftButtonDown && control)
    }
}
