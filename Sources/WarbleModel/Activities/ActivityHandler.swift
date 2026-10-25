import Foundation

/// The process on the other end of a connection, as the socket read it from the connection and never from the line.
public struct ActivitySender: Equatable, Sendable {
    /// The connection's number, which `ActivityKey.client` and `ActivityChannel` use.
    public var client: Int
    /// A signed app's team ID and signing identifier, or a script's executable.
    public var identifier: String
    /// A signed app's name. A script names itself with `from`.
    public var name: String
    /// A signed app's bundle identifier, which names its icon, or `nil` for a script.
    public var bundleIdentifier: String?

    public init(client: Int, identifier: String, name: String, bundleIdentifier: String? = nil) {
        self.client = client
        self.identifier = identifier
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    var isScript: Bool { bundleIdentifier == nil }
}

/// The one line Warble answers each request with: `ok`, or an error that is a sentence.
public struct ActivityReply: Codable, Equatable, Sendable {
    public var v = ActivityRequest.version
    /// The `op` this answers, when the line got far enough to name one.
    public var re: String?
    public var ok: Bool
    public var error: String?

    public static func success(_ operation: String) -> ActivityReply {
        ActivityReply(re: operation, ok: true)
    }

    public static func failure(_ error: ActivityError) -> ActivityReply {
        ActivityReply(re: error.operation, ok: false, error: error.message)
    }

    /// The reply as one line, newline included.
    public var line: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return ((try? encoder.encode(self)) ?? Data()) + Data("\n".utf8)
    }
}

/// Answers an app's lines. It checks each against the limits, then does what the notch would: it dispatches the action, so
/// an activity shows at once. The socket calls it on the main actor, where the store runs.
@MainActor
public final class ActivityHandler {
    private let state: () -> AppState
    private let dispatch: (AppAction) -> Void
    private let clock: any WallClock
    private var rates: [Int: ActivityRate] = [:]

    public init(state: @escaping () -> AppState, dispatch: @escaping (AppAction) -> Void, clock: any WallClock) {
        self.state = state
        self.dispatch = dispatch
        self.clock = clock
    }

    /// Takes one line from `sender` and answers it.
    public func handle(_ line: Data, from sender: ActivitySender) -> ActivityReply {
        let now = clock.now
        var rate = rates[sender.client] ?? ActivityRate()
        let allowed = rate.allow(at: now)
        rates[sender.client] = rate
        guard allowed else {
            return .failure(ActivityError("slow down; a connection may send \(ActivityLimits.linesPerSecond) lines a second"))
        }
        do throws(ActivityError) {
            let request = try ActivityRequest.decode(line, isScript: sender.isScript)
            try run(request, from: sender, at: now)
            return .success(request.name)
        } catch {
            return .failure(error)
        }
    }

    /// The connection closed: everything it started ends, and nothing is sent back.
    public func closed(client: Int) {
        rates[client] = nil
        dispatch(.activityClientClosed(client: client))
    }

    private func run(_ request: ActivityRequest, from sender: ActivitySender, at now: Date) throws(ActivityError) {
        let activities = state().activities
        let key = ActivityKey(client: sender.client, id: request.id)
        switch request.operation {
        case .start(let draft):
            let owner = Self.owner(of: draft, from: sender)
            guard activities.isOn else { throw ActivityError("Warble isn't showing activities; they're off in Settings") }
            guard !activities.blocked.contains(owner.identifier) else {
                throw ActivityError("\(owner.label) is turned off in Settings › Activities")
            }
            // A start with an id in use replaces that activity, so it doesn't count against the limits.
            let others = activities.items.filter { $0.key != key }
            guard others.count < ActivityLimits.activities else {
                throw ActivityError("Warble can show \(ActivityLimits.activities) activities at once")
            }
            guard others.filter({ $0.key.client == sender.client }).count < ActivityLimits.perConnection else {
                throw ActivityError("a connection can have \(ActivityLimits.perConnection) activities at once")
            }
            dispatch(.activityStarted(Activity(draft, client: sender.client, owner: owner, at: now)))
        case .update(_, let patch):
            guard activities.items.contains(where: { $0.key == key }) else {
                throw ActivityError("there's no activity with the id \"\(request.id)\"; it may have ended or been closed")
            }
            dispatch(.activityUpdated(key, patch))
        case .end:
            // Ending one that's gone is not a mistake: the user may have closed it first.
            dispatch(.activityEnded(key))
        }
    }

    /// A signed app is its signature. A script is the executable with the name it gave, so blocking one script doesn't block
    /// every script on the same interpreter.
    private static func owner(of draft: ActivityDraft, from sender: ActivitySender) -> ActivityOwner {
        guard sender.isScript, let from = draft.from else {
            return ActivityOwner(identifier: sender.identifier, name: sender.name, bundleIdentifier: sender.bundleIdentifier)
        }
        return ActivityOwner(identifier: "\(ActivityOwner.scriptPrefix)\(sender.identifier)|\(from)", name: from)
    }
}
