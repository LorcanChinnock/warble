import Foundation

public enum PreferenceKey {
    /// Whether Warble shows its icon in the menu bar. The notch's right-click menu works either way.
    public static let showMenuBarIcon = "showMenuBarIcon"
}

public struct Preferences {
    public static var defaults: [String: Any] {
        [
            PreferenceKey.showMenuBarIcon: true,
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

    /// Whether `keys`, the keys saved in Warble's defaults domain, hold any of Warble's own, so Warble was used before.
    /// Takes the saved keys rather than reading `UserDefaults`, which also answers with registered defaults.
    public static func hasSavedSettings(_ keys: some Sequence<String>) -> Bool {
        let own = Set(defaults.keys)
        return keys.contains { own.contains($0) }
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
}
