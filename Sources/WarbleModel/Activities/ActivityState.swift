import Foundation

/// The activities other apps show: whether Settings has them on, the apps it turned off, and the ones live now.
public struct ActivityState: Feature {
    /// Whether Settings has activities on, which starts off. Off, there is no socket and `items` is empty.
    public internal(set) var isOn: Bool
    /// The senders Settings turned off, by `ActivityOwner.identifier`.
    public internal(set) var blocked: Set<String>
    /// Every sender that has shown an activity, by `ActivityOwner.identifier`, with its name, for Settings' list.
    public internal(set) var apps: [String: String]
    /// The live activities, the newest start last, at most `ActivityLimits.activities`.
    public internal(set) var items: [Activity] = []

    public init(isOn: Bool = false, blocked: Set<String> = [], apps: [String: String] = [:]) {
        self.isOn = isOn
        self.blocked = blocked
        self.apps = apps
    }

    /// The earliest `endsAt`, or `nil` with nothing live, so `Store` arms one timer at most, and none without an activity.
    var deadline: Date? { items.map(\.endsAt).min() }

    /// Every activity in the order the card lists them: `high` first, then the newest start.
    public var ranked: [Activity] {
        let newest = items.reversed()
        return newest.filter { $0.priority == .high } + newest.filter { $0.priority != .high }
    }

    /// The one the wings draw.
    public var current: Activity? { ranked.first }

    mutating func reduce(_ action: AppAction, shared: SharedState, at now: Date) -> [AppEffect] {
        var effects: [AppEffect] = []
        switch action {
        case .activitiesChanged(let on):
            isOn = on
            if !on {
                // The socket closes, which every sender sees as a closed connection, so none is told.
                items = []
            }
        case .activityBlocklistChanged(let blocked):
            self.blocked = blocked
            effects += remove { blocked.contains($0.owner.identifier) }.map { .sendActivityEvent($0.key, .ended(.blocked)) }
        case .activityStarted(let activity):
            guard isOn, !blocked.contains(activity.owner.identifier) else { break }
            // A start with a key in use replaces that activity, and counts as the newest.
            var others = items
            others.removeAll { $0.key == activity.key }
            guard others.count < ActivityLimits.activities, others.filter({ $0.key.client == activity.key.client }).count < ActivityLimits.perConnection else { break }
            items = others + [activity]
            if apps[activity.owner.identifier] == nil {
                apps[activity.owner.identifier] = activity.owner.name
                effects.append(.saveActivityApps(apps))
            }
        case .activityUpdated(let key, let patch):
            if let index = items.firstIndex(where: { $0.key == key }) {
                items[index] = items[index].applying(patch, at: now)
            }
        case .activityEnded(let key):
            items.removeAll { $0.key == key }
        case .activityClientClosed(let client):
            items.removeAll { $0.key.client == client }
        case .activityButton(let key, let button):
            // A press on an activity or a button that's gone, such as after the connection closed, goes nowhere.
            if items.first(where: { $0.key == key })?.buttons.contains(where: { $0.id == button }) == true {
                effects += [.haptic, .sendActivityEvent(key, .button(button))]
            }
        case .activityDismissed(let key):
            effects += remove { $0.key == key }.map { .sendActivityEvent($0.key, .ended(.dismissed)) }
        case .tick:
            effects += remove { $0.endsAt <= now }.map { .sendActivityEvent($0.key, .ended(.expired)) }
        default:
            break
        }
        return effects
    }

    /// Takes out the activities `isRemoved` picks, and returns them in the order they started.
    private mutating func remove(where isRemoved: (Activity) -> Bool) -> [Activity] {
        let removed = items.filter(isRemoved)
        items.removeAll(where: isRemoved)
        return removed
    }
}
