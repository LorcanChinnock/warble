import Foundation

/// Who an activity belongs to, read from the connection and not from anything the sender says.
public struct ActivityOwner: Equatable, Hashable, Sendable {
    /// What Settings blocks by: a signed app's team ID and signing identifier, or a script's executable and `from`.
    public var identifier: String
    /// The app's name, or for a script the `from` it gave. The card shows a script's as "Script: <name>", which the views
    /// localize, since WarbleModel can't.
    public var name: String
    /// The app whose icon the wing draws, or `nil` for a script, which gets a generic mark.
    public var bundleIdentifier: String?

    public init(identifier: String, name: String, bundleIdentifier: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    public var isScript: Bool { bundleIdentifier == nil }

    /// What the owner is called in the protocol's errors and logs, which stay English.
    public var label: String { isScript ? "Script: \(name)" : name }

    /// Whether `identifier` is a script's, for Settings' list of apps, which holds identifiers with names.
    public static func isScript(identifier: String) -> Bool { identifier.hasPrefix(scriptPrefix) }

    static let scriptPrefix = "script|"
}

/// One activity: the connection's number and the sender's own name for it. Unique while the activity lives.
public struct ActivityKey: Hashable, Sendable {
    public var client: Int
    public var id: String

    public init(client: Int, id: String) {
        self.client = client
        self.id = id
    }
}

public enum ActivityTint: String, CaseIterable, Sendable {
    case white, red, orange, yellow, green, blue
}

/// A badge on the sender's icon. The view checks that the symbol exists, since the model can't.
public struct ActivityIcon: Equatable, Sendable {
    public var symbol: String
    public var tint: ActivityTint

    public init(symbol: String, tint: ActivityTint = .white) {
        self.symbol = symbol
        self.tint = tint
    }
}

/// A clock Warble draws from its start or end, so the sender needn't send updates.
public enum ActivityClock: Equatable, Sendable {
    case since(Date)
    case until(Date)
}

public struct ActivityButton: Equatable, Sendable {
    public var id: String
    public var label: String
    public var symbol: String?

    public init(id: String, label: String, symbol: String? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
    }
}

public enum ActivityPriority: String, Sendable {
    case normal, high
}

/// Something another app shows in the notch while it lives.
public struct Activity: Equatable, Sendable, Identifiable {
    public var key: ActivityKey
    public var owner: ActivityOwner
    public var title: String
    public var detail: String?
    public var badge: String?
    public var icon: ActivityIcon?
    public var clock: ActivityClock?
    public var buttons: [ActivityButton]
    public var priority: ActivityPriority
    /// When Warble ends the activity itself: the start or the last `update` that set `lasts`, plus `lasts`.
    public var endsAt: Date

    public var id: ActivityKey { key }

    public init(
        key: ActivityKey, owner: ActivityOwner, title: String, detail: String? = nil, badge: String? = nil, icon: ActivityIcon? = nil,
        clock: ActivityClock? = nil, buttons: [ActivityButton] = [], priority: ActivityPriority = .normal, endsAt: Date
    ) {
        self.key = key
        self.owner = owner
        self.title = title
        self.detail = detail
        self.badge = badge
        self.icon = icon
        self.clock = clock
        self.buttons = buttons
        self.priority = priority
        self.endsAt = endsAt
    }

    /// The activity a validated `start` asks for, starting at `now`.
    public init(_ draft: ActivityDraft, client: Int, owner: ActivityOwner, at now: Date) {
        self.init(
            key: ActivityKey(client: client, id: draft.id), owner: owner, title: draft.title, detail: draft.detail, badge: draft.badge,
            icon: draft.icon, clock: draft.clock, buttons: draft.buttons, priority: draft.priority, endsAt: now + draft.lasts
        )
    }

    /// The activity with `patch` applied at `now`.
    func applying(_ patch: ActivityPatch, at now: Date) -> Activity {
        var activity = self
        if let title = patch.title { activity.title = title }
        if let priority = patch.priority { activity.priority = priority }
        patch.detail.apply(to: &activity.detail)
        patch.badge.apply(to: &activity.badge)
        patch.icon.apply(to: &activity.icon)
        patch.clock.apply(to: &activity.clock)
        switch patch.buttons {
        case .keep: break
        case .clear: activity.buttons = []
        case .set(let buttons): activity.buttons = buttons
        }
        switch patch.lasts {
        case .keep: break
        case .clear: activity.endsAt = now + ActivityLimits.defaultLasts
        case .set(let lasts): activity.endsAt = now + lasts
        }
        return activity
    }
}

/// What an `update` does to a field it names.
public enum ActivityChange<Value: Equatable & Sendable>: Equatable, Sendable {
    case keep
    /// The field was `null`.
    case clear
    case set(Value)

    func apply(to field: inout Value?) {
        switch self {
        case .keep: break
        case .clear: field = nil
        case .set(let value): field = value
        }
    }
}

/// The fields an `update` changes. The rest stay as they were.
public struct ActivityPatch: Equatable, Sendable {
    /// These two can be changed but never cleared.
    public var title: String?
    public var priority: ActivityPriority?
    public var detail: ActivityChange<String> = .keep
    public var badge: ActivityChange<String> = .keep
    public var icon: ActivityChange<ActivityIcon> = .keep
    public var clock: ActivityChange<ActivityClock> = .keep
    public var buttons: ActivityChange<[ActivityButton]> = .keep
    /// `.clear` puts `lasts` back to the default, so no activity is ever without an end. Set, it counts again from the update.
    public var lasts: ActivityChange<TimeInterval> = .keep

    public init(
        title: String? = nil, priority: ActivityPriority? = nil, detail: ActivityChange<String> = .keep,
        badge: ActivityChange<String> = .keep, icon: ActivityChange<ActivityIcon> = .keep,
        clock: ActivityChange<ActivityClock> = .keep, buttons: ActivityChange<[ActivityButton]> = .keep,
        lasts: ActivityChange<TimeInterval> = .keep
    ) {
        self.title = title
        self.priority = priority
        self.detail = detail
        self.badge = badge
        self.icon = icon
        self.clock = clock
        self.buttons = buttons
        self.lasts = lasts
    }
}

/// What the sender can hear back. A replacement and an activity the sender ended itself send nothing.
public enum ActivityEvent: Equatable, Sendable {
    case button(String)
    case ended(Reason)

    public enum Reason: String, Sendable {
        /// The user closed it.
        case dismissed
        /// `lasts` ran out.
        case expired
        /// The user turned that app off in Settings.
        case blocked
    }

    /// The event as the line the sender reads, newline included.
    public func line(id: String) -> Data {
        struct Line: Encodable {
            var v = ActivityRequest.version
            var event: String
            var id: String
            var button: String?
            var reason: String?
        }
        let line = switch self {
        case .button(let button): Line(event: "button", id: id, button: button)
        case .ended(let reason): Line(event: "ended", id: id, reason: reason.rawValue)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // A struct of strings and a number always encodes.
        return ((try? encoder.encode(line)) ?? Data()) + Data("\n".utf8)
    }
}
