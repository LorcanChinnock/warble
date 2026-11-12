import Foundation

/// One item in Warble's menus, the menu bar menu and the notch's right-click menu, which `AppMenu.items` puts in order.
public enum AppMenuItem: Equatable, Sendable {
    /// "Open Spotify": the app the notch follows. Right-click menu only.
    case openApp
    /// "Copy Song and Artist", while the notch shows a song with a title. Right-click menu only.
    case copySong
    /// "About Warble", which opens Settings on the About tab.
    case about
    /// Check for Updates…, or what an update under way says instead.
    case update(UpdateMenuItem)
    /// "Settings… ⌘,".
    case settings
    /// "Quit Warble ⌘Q".
    case quit
    case separator
}

/// The menus' update item. Each case opens the update window, apart from a check that can't run.
public enum UpdateMenuItem: Equatable, Sendable {
    /// "Check for Updates…", dimmed while Sparkle can't check, as in a build with no feed or while a check runs.
    case check(enabled: Bool)
    /// "Update to 0.2.0…" with the accent dot: a scheduled check found it and the person hasn't looked at it yet. A
    /// menu bar app's window can open behind others, so the menu offers it too.
    case waiting(version: String)
    /// "Downloading 0.2.0 (53%)…": an update is downloading, whether or not its window is open. `percent` is nil
    /// while the server hasn't said how big the download is.
    case downloading(version: String, percent: Int?)

    /// - Parameters:
    ///   - pendingVersion: `Updater.pendingVersion`, a version a scheduled check found that the person hasn't looked at.
    ///   - canCheck: Whether Sparkle can start a check now.
    ///   - phase: The update window's state, or nil when no update is under way.
    ///   - version: The version the update window is about.
    ///   - fraction: How much of the download has arrived, from 0 to 1, or nil while its size isn't known.
    public init(pendingVersion: String?, canCheck: Bool, phase: UpdatePhase?, version: String, fraction: Double?) {
        switch phase {
        case .downloading:
            self = .downloading(version: version, percent: fraction.map { Int(($0 * 100).rounded(.down)) })
            return
        case .preparing:
            // Unpacking takes a moment after the last byte arrives, and the window still says it's downloading.
            self = .downloading(version: version, percent: 100)
            return
        default:
            break
        }
        if let pendingVersion {
            self = .waiting(version: pendingVersion)
        } else {
            self = .check(enabled: canCheck)
        }
    }

    /// Whether the item can be chosen.
    public var isEnabled: Bool {
        if case .check(let enabled) = self {
            return enabled
        }
        return true
    }

    /// Whether the item carries the accent dot, as the menu bar icon does while an update waits.
    public var hasDot: Bool {
        if case .waiting = self {
            return true
        }
        return false
    }
}

/// What Warble's menus hold and in what order, in the conventional macOS order: About Warble, Check for Updates…,
/// Settings… and Quit Warble, each group between separators. The notch's right-click menu puts the song's own items
/// first, then the same items in the same order.
public enum AppMenu {
    /// The menu bar menu.
    public static func items(update: UpdateMenuItem) -> [AppMenuItem] {
        [.about, .update(update), .separator, .settings, .separator, .quit]
    }

    /// The notch's right-click menu. `openApp` is whether the app the notch follows can be opened; `copySong` whether
    /// a song with a title shows.
    public static func items(update: UpdateMenuItem, openApp: Bool, copySong: Bool) -> [AppMenuItem] {
        var song: [AppMenuItem] = []
        if openApp {
            song.append(.openApp)
        }
        if copySong {
            song.append(.copySong)
        }
        return (song.isEmpty ? [] : song + [.separator]) + items(update: update)
    }
}
