import AppKit
import CoreServices
import Foundation

extension Doctor {
    /// The facts the checks need, with `adapter` as the app last saw it. While the adapter works no check needs to know
    /// about Automation, so macOS isn't asked. Asking can wait on the permission service, so it runs off the main thread.
    public static func facts(adapter: Adapter) async -> Facts {
        var facts = Facts(adapter: adapter, macOS: .running)
        if adapter != .working {
            facts.automation = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: ScriptedPlayer.allCases.map { ($0, automation(of: $0)) })
            }.value
        }
        return facts
    }

    /// Whether Warble may script `player`, without asking: macOS only answers for a player that's running.
    static func automation(of player: ScriptedPlayer) -> Automation {
        // The descriptor owns the data `aeDesc` points to, so it has to outlive the call.
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: player.bundleIdentifier)
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty,
              var target = descriptor.aeDesc?.pointee else {
            return .notRunning
        }
        let status = withExtendedLifetime(descriptor) {
            AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
        }
        switch status {
        case noErr: return .allowed
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        // errAEEventWouldRequireUserConsent, and anything else macOS might answer.
        default: return .notAsked
        }
    }
}

extension Doctor.Version {
    /// The macOS this Mac runs.
    public static var running: Self {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Self(os.majorVersion, os.minorVersion, os.patchVersion)
    }
}

extension ScriptedPlayer {
    /// The app's name, which isn't translated.
    public var name: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }
}

extension Doctor.Check {
    public var title: String {
        switch kind {
        case .adapter: String(localized: "Reading what's playing")
        case .macOS:
            switch finding {
            case .macOSSupported(let version), .macOSNewer(let version): String(localized: "macOS \(version.description)")
            default: String(localized: "macOS")
            }
        case .automation: String(localized: "Permission")
        case .players: String(localized: "Players")
        }
    }

    public var detail: String {
        switch finding {
        case .adapterWorking: String(localized: "Works with any app that plays.")
        case .adapterMissing: String(localized: "Part of Warble is missing, so it can only follow Music and Spotify.")
        case .adapterBlocked: String(localized: "macOS won't let Warble read what's playing, so it only follows Music and Spotify.")
        case .adapterUnsteady: String(localized: "This kept stopping, so Warble only follows Music and Spotify until you open it again.")
        case .macOSSupported: String(localized: "Supported.")
        case .macOSNewer: String(localized: "Newer than this version of Warble. An update may fix reading what's playing.")
        case .automationNotNeeded: String(localized: "Not needed while Warble can read what's playing.")
        case .automationAllowed(let players): String(localized: "Warble may control \(Self.names(players)).")
        case .automationDenied(let players): String(localized: "Warble isn't allowed to control \(Self.names(players)). Turn it on under Warble in Privacy & Security › Automation.")
        case .automationNotAsked(let players): String(localized: "macOS will ask the first time \(Self.names(players)) plays.")
        case .automationUnknown: String(localized: "Open Music or Spotify to check.")
        case .playersAny: String(localized: "Any app that plays, including your browser.")
        case .playersFollowing(let players): String(localized: "Following \(Self.names(players)). Other apps won't show for now.")
        case .playersNoneOpen: String(localized: "Only Music and Spotify can show for now.")
        }
    }

    /// The fix's button, or `nil` when there's nothing to do.
    public var fixTitle: String? {
        switch fix {
        case .reinstall: String(localized: "Download Warble")
        case .openAgain: String(localized: "Open Warble Again")
        case .checkForUpdates: String(localized: "Check for Updates")
        case .openAutomationSettings: String(localized: "Open Settings")
        case .openPlayer(let player): String(localized: "Open \(player.name)")
        case nil: nil
        }
    }

    /// "Music and Spotify", in the user's language.
    private static func names(_ players: [ScriptedPlayer]) -> String {
        ListFormatter.localizedString(byJoining: players.map(\.name))
    }
}

extension Doctor {
    /// The card's heading for `checks`.
    public static func headline(_ checks: [Check]) -> String {
        checks.contains { $0.outcome == .fail }
            ? String(localized: "Warble can't see everything")
            : String(localized: "Everything's working")
    }
}
