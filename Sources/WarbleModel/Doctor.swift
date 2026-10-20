import Foundation

/// Why Warble might not see what's playing, from facts the app gathers when something changes: whether the adapter
/// runs, the macOS version, the Automation permission the AppleScript fallback needs, and which players it can follow.
/// Each check that isn't passing says how to fix it. The words live in WarbleCore, so every outcome is tested on Linux.
public enum Doctor {
    /// How the adapter, which reads what any app plays, is doing.
    public enum Adapter: Equatable, Sendable {
        /// Running, or about to be.
        case working
        /// Not in the app, as when a file of it has been removed.
        case missing
        /// Warble gave up on it until it's opened again. `testStatus` is how its last `test` exited, `nil` if none ran.
        case stopped(testStatus: Int32?)
    }

    /// Whether Warble may script a player, as macOS answers without asking the user.
    public enum Automation: Equatable, Sendable {
        case allowed
        case denied
        /// macOS will ask the first time Warble scripts the player.
        case notAsked
        /// Only a running player can be asked about.
        case notRunning
    }

    public struct Version: Equatable, Sendable, CustomStringConvertible {
        public var major: Int
        public var minor: Int
        public var patch: Int

        public init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
            self.major = major
            self.minor = minor
            self.patch = patch
        }

        public var description: String {
            patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
        }
    }

    public struct Facts: Equatable, Sendable {
        public var adapter: Adapter
        public var macOS: Version
        public var automation: [ScriptedPlayer: Automation]

        public init(adapter: Adapter, macOS: Version, automation: [ScriptedPlayer: Automation] = [:]) {
            self.adapter = adapter
            self.macOS = macOS
            self.automation = automation
        }

        /// The players that are open, which are the only ones macOS answers about.
        public var runningPlayers: [ScriptedPlayer] {
            ScriptedPlayer.allCases.filter { (automation[$0] ?? .notRunning) != .notRunning }
        }
    }

    public enum Outcome: String, Sendable {
        case pass
        /// Works, but not as well as it could.
        case warn
        case fail
        /// Couldn't be checked yet.
        case unknown
    }

    public enum Kind: String, CaseIterable, Sendable {
        case adapter, macOS, automation, players
    }

    /// What a check found, with what the words need.
    public enum Finding: Equatable, Sendable {
        case adapterWorking
        case adapterMissing
        /// macOS won't let the adapter run, such as after an update to macOS.
        case adapterBlocked
        /// It ran, but kept stopping or timing out.
        case adapterUnsteady
        case macOSSupported(Version)
        /// Newer than any macOS this Warble was tried on, which may be why the adapter stopped.
        case macOSNewer(Version)
        /// The adapter works, so no player needs scripting.
        case automationNotNeeded
        case automationAllowed([ScriptedPlayer])
        case automationDenied([ScriptedPlayer])
        case automationNotAsked([ScriptedPlayer])
        /// No player is open to ask about.
        case automationUnknown
        case playersAny
        case playersFollowing([ScriptedPlayer])
        /// No player the fallback may follow is open.
        case playersNoneOpen
    }

    /// What the user can do about a check, one button each.
    public enum Fix: Equatable, Sendable {
        /// Download Warble again.
        case reinstall
        /// Quit and open Warble again, which tries the adapter again.
        case openAgain
        case checkForUpdates
        /// System Settings › Privacy & Security › Automation.
        case openAutomationSettings
        case openPlayer(ScriptedPlayer)
    }

    public struct Check: Equatable, Sendable {
        public var kind: Kind
        public var outcome: Outcome
        public var finding: Finding
        public var fix: Fix?

        public init(_ kind: Kind, _ outcome: Outcome, _ finding: Finding, fix: Fix? = nil) {
            self.kind = kind
            self.outcome = outcome
            self.finding = finding
            self.fix = fix
        }
    }

    /// The newest macOS this Warble has been tried on.
    public static let newestTestedMacOS = 27

    /// Every check, the one most likely to be the cause first.
    public static func checks(_ facts: Facts) -> [Check] {
        [adapter(facts), macOS(facts), automation(facts), players(facts)]
    }

    /// Whether to show the "!" on the notch: a check failed that the user hasn't put off with Not now.
    public static func needsAttention(_ checks: [Check], dismissed: Set<Kind> = []) -> Bool {
        checks.contains { $0.outcome == .fail && !dismissed.contains($0.kind) }
    }

    static func adapter(_ facts: Facts) -> Check {
        switch facts.adapter {
        case .working:
            return Check(.adapter, .pass, .adapterWorking)
        case .missing:
            return Check(.adapter, .fail, .adapterMissing, fix: .reinstall)
        // 3 and 4 are timeouts on an adapter that works, and without a test the stream kept stopping after it passed.
        case .stopped(testStatus: 0?), .stopped(testStatus: 3?), .stopped(testStatus: 4?), .stopped(testStatus: nil):
            return Check(.adapter, .fail, .adapterUnsteady, fix: .openAgain)
        case .stopped:
            return Check(.adapter, .fail, .adapterBlocked, fix: .checkForUpdates)
        }
    }

    static func macOS(_ facts: Facts) -> Check {
        guard facts.macOS.major > newestTestedMacOS, facts.adapter != .working else {
            return Check(.macOS, .pass, .macOSSupported(facts.macOS))
        }
        return Check(.macOS, .warn, .macOSNewer(facts.macOS), fix: .checkForUpdates)
    }

    static func automation(_ facts: Facts) -> Check {
        guard facts.adapter != .working else {
            return Check(.automation, .pass, .automationNotNeeded)
        }
        let players = { (access: Automation) in ScriptedPlayer.allCases.filter { facts.automation[$0] == access } }
        if !players(.denied).isEmpty {
            return Check(.automation, .fail, .automationDenied(players(.denied)), fix: .openAutomationSettings)
        }
        if !players(.allowed).isEmpty {
            return Check(.automation, .pass, .automationAllowed(players(.allowed)))
        }
        if !players(.notAsked).isEmpty {
            return Check(.automation, .pass, .automationNotAsked(players(.notAsked)))
        }
        return Check(.automation, .unknown, .automationUnknown)
    }

    static func players(_ facts: Facts) -> Check {
        guard facts.adapter != .working else {
            return Check(.players, .pass, .playersAny)
        }
        // A player Warble may not script can't be followed, which the Automation check explains.
        let running = facts.runningPlayers
        let following = running.filter { facts.automation[$0] != .denied }
        guard following.isEmpty else {
            return Check(.players, .warn, .playersFollowing(following))
        }
        return Check(.players, .warn, .playersNoneOpen, fix: running.isEmpty ? .openPlayer(.music) : nil)
    }
}
