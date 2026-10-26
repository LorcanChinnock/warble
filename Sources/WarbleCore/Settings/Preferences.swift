import Foundation

public enum PreferenceKey {
    /// Whether Warble shows its icon in the menu bar. The notch's right-click menu works either way.
    public static let showMenuBarIcon = "showMenuBarIcon"
    /// How large Warble draws its own text, a `TextSize`.
    public static let textSize = "textSize"
    /// Each display's `VirtualNotchRule` raw value, by `NotchDisplay.id`. A display missing from it follows its default.
    public static let virtualNotch = "virtualNotch"
    /// How many seconds a paused track stays in the notch before it goes Idle.
    public static let stayVisibleAfterPausing = "stayVisibleAfterPausing"
    /// Whether a virtual notch shows the title of what's playing in its middle.
    public static let virtualTitle = "virtualTitle"


}

/// Typed read access to settings; `@Setting` in views uses the same keys and `Preferences.defaults`.
public struct Preferences {
    public static var defaults: [String: Any] {
        [
            PreferenceKey.showMenuBarIcon: true,
            PreferenceKey.textSize: TextSize.standard.rawValue,
            PreferenceKey.virtualNotch: [String: String](),
            PreferenceKey.stayVisibleAfterPausing: IdleAfterPause.defaultDelay,
            PreferenceKey.virtualTitle: true,
        ]
    }

    private let store: UserDefaults

    /// Call `registerDefaults()` on `store` once before reading.
    public init(store: UserDefaults = .standard) {
        self.store = store
    }

    public static func registerDefaults(in store: UserDefaults = .standard) {
        store.register(defaults: defaults)
    }

    /// Removes every stored value so the registered defaults apply again.
    public static func resetAll(in store: UserDefaults = .standard) {
        for key in defaults.keys {
            store.removeObject(forKey: key)
        }
    }

    public var showMenuBarIcon: Bool {
        store.bool(forKey: PreferenceKey.showMenuBarIcon)
    }

    public var textSize: TextSize {
        TextSize(rawValue: store.string(forKey: PreferenceKey.textSize) ?? "") ?? .standard
    }

    /// The rules the user has set, leaving out any that isn't a rule.
    public var virtualNotchRules: [String: VirtualNotchRule] {
        let stored = store.dictionary(forKey: PreferenceKey.virtualNotch) as? [String: String] ?? [:]
        return stored.compactMapValues(VirtualNotchRule.init(rawValue:))
    }

    /// Never negative, so a stray value goes Idle at once rather than never.
    public var stayVisibleAfterPausing: TimeInterval {
        max(store.double(forKey: PreferenceKey.stayVisibleAfterPausing), 0)
    }

    public var virtualTitle: Bool {
        store.bool(forKey: PreferenceKey.virtualTitle)
    }
}
