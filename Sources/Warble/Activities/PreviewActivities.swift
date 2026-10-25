import Foundation
import WarbleCore

/// Activities for `-notchPreviewState activity`, so the notch can be seen with them without a socket. They are made up:
/// a recording with a clock and a Stop button, a script with a badge and a countdown. `-notchPreviewActivities 3` shows
/// more than the first, up to the three Warble shows at once.
enum PreviewActivities {
    @MainActor
    static func start(_ count: Int, in store: Store, now: Date = .now) {
        store.dispatch(.activitiesChanged(true))
        for activity in samples(now: now).prefix(max(1, min(count, ActivityLimits.activities))) {
            store.dispatch(.activityStarted(activity))
        }
    }

    private static func samples(now: Date) -> [Activity] {
        let recorder = ActivityOwner(identifier: "preview.recorder", name: "QuickTime Player", bundleIdentifier: "com.apple.QuickTimePlayerX")
        let backup = ActivityOwner(identifier: "script|preview|backup", name: "backup")
        let download = ActivityOwner(identifier: "preview.safari", name: "Safari", bundleIdentifier: "com.apple.Safari")
        return [
            Activity(
                key: ActivityKey(client: 1, id: "recording"), owner: recorder, title: "Recording Display 1", detail: "Saves to Desktop",
                icon: ActivityIcon(symbol: "record.circle", tint: .red), clock: .since(now),
                buttons: [ActivityButton(id: "stop", label: "Stop", symbol: "stop.fill")], endsAt: now + ActivityLimits.defaultLasts
            ),
            Activity(
                key: ActivityKey(client: 2, id: "backup"), owner: backup, title: "Backing up Photos", badge: "42%",
                icon: ActivityIcon(symbol: "externaldrive", tint: .blue), endsAt: now + ActivityLimits.defaultLasts
            ),
            Activity(
                key: ActivityKey(client: 3, id: "download"), owner: download, title: "Downloading macOS",
                icon: ActivityIcon(symbol: "arrow.down.circle", tint: .green), clock: .until(now + 600), endsAt: now + ActivityLimits.defaultLasts
            ),
        ]
    }
}
