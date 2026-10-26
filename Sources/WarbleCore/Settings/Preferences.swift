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
    /// Whether the new track's title and artist slide out of the notch for a moment when the track changes.
    public static let trackChangeToast = "trackChangeToast"
    /// Whether a podcast or audiobook has back 15 and forward 30 seconds in place of previous and next.
    public static let podcastSkips = "podcastSkips"
    /// Whether a virtual notch shows the title of what's playing in its middle.
    public static let virtualTitle = "virtualTitle"


    /// Whether the welcome window has been seen, or didn't need to be because Warble was in use before it existed.
    public static let hasSeenWelcome = "hasSeenWelcome"

    public static func hotkey(_ action: WarbleAction) -> String { "hotkey.\(action.rawValue)" }
}

/// Typed read access to settings; `@Setting` in views uses the same keys and `Preferences.defaults`.
public struct Preferences {
    public static var defaults: [String: Any] {
        var values: [String: Any] = [
            PreferenceKey.showMenuBarIcon: true,
            PreferenceKey.textSize: TextSize.standard.rawValue,
            PreferenceKey.virtualNotch: [String: String](),
            PreferenceKey.stayVisibleAfterPausing: IdleAfterPause.defaultDelay,
            PreferenceKey.trackChangeToast: false,
            PreferenceKey.podcastSkips: false,
            PreferenceKey.virtualTitle: true,
            PreferenceKey.hasSeenWelcome: false,
        ]
        for action in WarbleAction.allCases {
            values[PreferenceKey.hotkey(action)] = action.defaultCombo?.encoded ?? ""
        }
        return values
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
        return keys.contains { own.contains($0) || $0.hasPrefix("hotkey.") }
    }

    /// Removes every stored value so the registered defaults apply again.
    public static func resetAll(in store: UserDefaults = .standard) {
        for key in defaults.keys {
            store.removeObject(forKey: key)
        }
    }

    /// Whether this launch is the first, so the welcome window opens. `saved` is Warble's saved defaults domain, which a
    /// Warble in use before the window existed has settings in; `UserDefaults` itself also answers with registered
    /// defaults, so it can't tell.
    public static func isFirstLaunch(saved: [String: Any]) -> Bool {
        guard saved[PreferenceKey.hasSeenWelcome] as? Bool != true else { return false }
        return !hasSavedSettings(saved.keys.filter { $0 != PreferenceKey.hasSeenWelcome })
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

    public var trackChangeToast: Bool {
        store.bool(forKey: PreferenceKey.trackChangeToast)
    }

    public var podcastSkips: Bool {
        store.bool(forKey: PreferenceKey.podcastSkips)
    }

    public var virtualTitle: Bool {
        store.bool(forKey: PreferenceKey.virtualTitle)
    }

    /// `nil` means the user cleared the shortcut.
    public func hotkey(for action: WarbleAction) -> KeyCombo? {
        KeyCombo(encoded: store.string(forKey: PreferenceKey.hotkey(action)) ?? "")
    }
}
