import Foundation

/// A command from outside Warble: a `warble://` link now, and later the command line and Shortcuts.
/// Each is one more way in for the same table, and each does what the matching button in the notch does, so `action`
/// is the `AppAction` that button dispatches.
public enum RemoteCommand: Equatable, Sendable {
    case play
    case pause
    case toggle
    case next
    case previous
    /// To a position, in seconds from the start of the track.
    case seek(seconds: TimeInterval)
    /// The output volume, from 0 to 100.
    case volume(percent: Int)
    /// Moves the sound to the output with this name, or the start of it. Only the command line has it, since matching a
    /// name needs the outputs, which the handler reads (`RemoteHandler`).
    case output(name: String)
    /// Opens the notch on the pointer's display with the keyboard in it, as the Open notch shortcut does.
    case expand
    /// Opens Settings, on the section named, which is one of `settingsSections`, or on the one that was last open.
    case settings(section: String?)

    /// The schemes Warble answers. A release registers `warble`, and WarbleDev registers `warble-dev` (scripts/bundle.sh),
    /// so the two can run side by side without one answering links meant for the other.
    public static let schemes: Set<String> = ["warble", "warble-dev"]

    /// The names of the Settings sections a link can open, which are `SettingsSection`'s raw values.
    public static let settingsSections: Set<String> = ["general", "notch", "shortcuts", "developer", "about"]

    /// What `reduce` dispatches for the command, or `nil` for one that isn't one action: opening Settings is an effect,
    /// and an output is picked by name first.
    public var action: AppAction? {
        switch self {
        case .play: .command(.play)
        case .pause: .command(.pause)
        case .toggle: .perform(.playPause)
        case .next: .perform(.nextTrack)
        case .previous: .perform(.previousTrack)
        case .seek(let seconds): .command(.seek(to: seconds))
        case .volume(let percent): .setVolume(Double(percent) / 100)
        case .expand: .perform(.openNotch)
        case .settings, .output: nil
        }
    }

    /// The seconds in `text`, a whole or decimal number that isn't negative, or `nil`.
    public static func seconds(_ text: String) -> TimeInterval? {
        guard let seconds = Double(text), seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    /// The percent in `text`, a whole number from 0 to 100, or `nil`.
    public static func percent(_ text: String) -> Int? {
        guard let percent = Int(text), (0...100).contains(percent) else { return nil }
        return percent
    }

    /// The command a `warble://` or `warble-dev://` link asks for, or `nil` for any other link, an unknown route, a
    /// missing or bad value or a section that doesn't exist.
    ///
    /// - `warble://toggle`, `play`, `pause`, `next`, `previous`
    /// - `warble://seek?seconds=90`
    /// - `warble://volume?percent=40`
    /// - `warble://expand`
    /// - `warble://settings` or `warble://settings?section=shortcuts`
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), Self.schemes.contains(scheme),
              let route = components.host?.lowercased()
        else { return nil }
        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        switch route {
        case "play": self = .play
        case "pause": self = .pause
        case "toggle": self = .toggle
        case "next": self = .next
        case "previous": self = .previous
        case "expand": self = .expand
        case "seek":
            guard let seconds = value("seconds").flatMap(Self.seconds) else { return nil }
            self = .seek(seconds: seconds)
        case "volume":
            guard let percent = value("percent").flatMap(Self.percent) else { return nil }
            self = .volume(percent: percent)
        case "settings":
            guard let section = value("section") else {
                self = .settings(section: nil)
                return
            }
            guard Self.settingsSections.contains(section) else { return nil }
            self = .settings(section: section)
        default:
            return nil
        }
    }
}
