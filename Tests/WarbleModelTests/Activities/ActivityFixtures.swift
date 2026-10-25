import Foundation
@testable import WarbleModel

let activityStart = Date(timeIntervalSinceReferenceDate: 800_000_000)

let shot = ActivityOwner(identifier: "TEAM.dev.shot", name: "Shot", bundleIdentifier: "dev.shot")
let backup = ActivityOwner(identifier: "script|/usr/bin/python3|backup", name: "backup")

/// An activity for `id` on connection `client`, lasting `lasts` seconds from `activityStart` unless told otherwise.
func activity(
    _ id: String = "recording", client: Int = 1, owner: ActivityOwner = shot, title: String = "Recording", priority: ActivityPriority = .normal,
    buttons: [ActivityButton] = [ActivityButton(id: "stop", label: "Stop")], lasts: TimeInterval = 3600
) -> Activity {
    Activity(
        key: ActivityKey(client: client, id: id), owner: owner, title: title, buttons: buttons, priority: priority,
        endsAt: activityStart + lasts
    )
}
