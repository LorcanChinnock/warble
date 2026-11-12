import Foundation

/// Whether to open the first-run window: once, at the first launch of a new install, and never for someone updating from
/// an earlier version. It reads the keys in Warble's own stored settings (the app's persistent domain, not the launch
/// arguments or the global domain), and must read them before Sparkle starts, because Sparkle stores
/// `SUHasLaunchedBefore` on its first start.
public enum FirstRun {
    /// Stored once the window has opened, so it never opens again.
    public static let shownKey = "firstRunShown"

    /// Keys that only an earlier launch can have stored. Every release has had Sparkle, which stores
    /// `SUHasLaunchedBefore` on its first start, even for someone who never opened Settings; the others are the
    /// settings an earlier version may have saved.
    public static let earlierLaunchKeys: Set<String> = [
        shownKey,
        "SUHasLaunchedBefore",
        "SULastCheckTime",
        "SUEnableAutomaticChecks",
        "virtualTitle",
        "pauseDelay",
        "virtualNotch",
        "cardSize",
        "notchFont",
        "favouriteHeart",
    ]

    /// Whether the window opens, given the keys Warble has stored.
    public static func opens(storedKeys: some Sequence<String>) -> Bool {
        !storedKeys.contains { earlierLaunchKeys.contains($0) }
    }
}
