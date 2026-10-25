import Foundation
import Testing
@testable import WarbleModel

private let start = activityStart

private func on() -> AppState {
    var state = AppState()
    _ = reduce(&state, .activitiesChanged(true), now: start)
    return state
}

private func ending(_ key: ActivityKey, _ reason: ActivityEvent.Reason) -> AppEffect {
    .sendActivityEvent(key, .ended(reason))
}

// MARK: The setting

@Test func activitiesStartOffAndAskForNothing() {
    var state = AppState()
    #expect(!state.listensForActivities)
    #expect(reduce(&state, .launched(firstRun: false), now: start).isEmpty)
    #expect(state.deadline == nil)
}

@Test func anActivityStartedWhileTheSettingIsOffIsIgnored() {
    var state = AppState()
    #expect(reduce(&state, .activityStarted(activity()), now: start).isEmpty)
    #expect(state.activities.items.isEmpty)
}

@Test func turningActivitiesOnAsksForTheSocketOnce() {
    var state = AppState()
    #expect(reduce(&state, .activitiesChanged(true), now: start) == [.listenForActivities(true)])
    #expect(reduce(&state, .activitiesChanged(true), now: start).isEmpty)
    #expect(!reduce(&state, .tick, now: start + 1).contains(.listenForActivities(true)))
}

@Test func aLaunchWithActivitiesOnOpensTheSocketAtTheFirstAction() {
    var state = AppState(showsActivities: true)
    #expect(reduce(&state, .launched(firstRun: false), now: start) == [.listenForActivities(true)])
    #expect(reduce(&state, .tick, now: start).isEmpty)
}

@Test func turningActivitiesOffClosesTheSocketAndEndsEveryActivityWithoutTellingAnyone() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    #expect(reduce(&state, .activitiesChanged(false), now: start) == [.listenForActivities(false)])
    #expect(state.activities.items.isEmpty)
    #expect(state.deadline == nil)
}

// MARK: Starting

@Test func aStartAddsTheActivityAndRemembersItsSender() {
    var state = on()
    let effects = reduce(&state, .activityStarted(activity()), now: start)
    #expect(state.activities.items == [activity()])
    #expect(effects == [.saveActivityApps(["TEAM.dev.shot": "Shot"])])
}

@Test func aSenderIsRememberedOnceAndOnlyWhenNew() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a")), now: start)
    #expect(reduce(&state, .activityStarted(activity("b")), now: start).isEmpty)
    let effects = reduce(&state, .activityStarted(activity("c", client: 2, owner: backup)), now: start)
    #expect(effects == [.saveActivityApps(["TEAM.dev.shot": "Shot", backup.identifier: "backup"])])
}

@Test func aStartWithAKeyInUseReplacesTheActivityAndCountsAsTheNewest() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", title: "First")), now: start)
    _ = reduce(&state, .activityStarted(activity("b")), now: start)
    let effects = reduce(&state, .activityStarted(activity("a", title: "Second")), now: start)
    #expect(state.activities.items.map(\.title) == ["Recording", "Second"])
    // The sender knows it replaced the activity, so nothing is sent back.
    #expect(effects.isEmpty)
}

@Test func theSameIDOnAnotherConnectionIsAnotherActivity() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", client: 1)), now: start)
    _ = reduce(&state, .activityStarted(activity("a", client: 2)), now: start)
    #expect(state.activities.items.count == 2)
}

@Test func aConnectionHasTwoActivitiesAtMost() {
    var state = on()
    for id in ["a", "b", "c"] {
        _ = reduce(&state, .activityStarted(activity(id, client: 1)), now: start)
    }
    #expect(state.activities.items.map(\.key.id) == ["a", "b"])
    // A replacement is not a third.
    _ = reduce(&state, .activityStarted(activity("b", client: 1, title: "Again")), now: start)
    #expect(state.activities.items.map(\.title) == ["Recording", "Again"])
}

@Test func threeActivitiesShowAtOnceAcrossApps() {
    var state = on()
    for (client, id) in [(1, "a"), (1, "b"), (2, "c"), (3, "d")] {
        _ = reduce(&state, .activityStarted(activity(id, client: client)), now: start)
    }
    #expect(state.activities.items.map(\.key.id) == ["a", "b", "c"])
}

@Test func anAppTurnedOffInSettingsCantStart() {
    var state = on()
    _ = reduce(&state, .activityBlocklistChanged([shot.identifier]), now: start)
    #expect(reduce(&state, .activityStarted(activity()), now: start).isEmpty)
    #expect(state.activities.items.isEmpty)
    #expect(state.activities.apps.isEmpty)
}

// MARK: Updating and ending

@Test func anUpdateChangesTheNamedFieldsAndKeepsItsPlace() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a")), now: start)
    _ = reduce(&state, .activityStarted(activity("b")), now: start)
    var first = activity("a")
    first.detail = "Saves to Desktop"
    _ = reduce(&state, .activityUpdated(first.key, ActivityPatch(detail: .set("Saves to Desktop"))), now: start)
    #expect(state.activities.items == [first, activity("b")])
}

@Test func anUpdateClearsOnlyWhatItSetToNull() {
    var state = on()
    var full = activity()
    full.detail = "Detail"
    full.badge = "REC"
    full.icon = ActivityIcon(symbol: "record.circle", tint: .red)
    full.clock = .since(start)
    _ = reduce(&state, .activityStarted(full), now: start)
    _ = reduce(&state, .activityUpdated(full.key, ActivityPatch(detail: .clear, clock: .clear, buttons: .clear)), now: start)
    let item = state.activities.items[0]
    #expect(item.detail == nil && item.clock == nil && item.buttons.isEmpty)
    #expect(item.badge == "REC" && item.icon != nil)
}

@Test func anUpdateCanChangeTheTitleAndPriority() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    _ = reduce(&state, .activityUpdated(activity().key, ActivityPatch(title: "Paused", priority: .high)), now: start)
    #expect(state.activities.items[0].title == "Paused")
    #expect(state.activities.items[0].priority == .high)
}

@Test func anUpdateForAnActivityThatsGoneDoesNothing() {
    var state = on()
    #expect(reduce(&state, .activityUpdated(activity().key, ActivityPatch(title: "Paused")), now: start).isEmpty)
    #expect(state.activities.items.isEmpty)
}

@Test func anUpdateThatSetsLastsCountsAgainFromTheUpdate() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity(lasts: 60)), now: start)
    _ = reduce(&state, .activityUpdated(activity().key, ActivityPatch(detail: .set("Still going"))), now: start + 30)
    #expect(state.deadline == start + 60)
    _ = reduce(&state, .activityUpdated(activity().key, ActivityPatch(lasts: .set(100))), now: start + 30)
    #expect(state.deadline == start + 130)
}

@Test func lastsSetToNullIsTheDefaultAnHourFromTheUpdate() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity(lasts: 60)), now: start)
    _ = reduce(&state, .activityUpdated(activity().key, ActivityPatch(lasts: .clear)), now: start + 30)
    #expect(state.deadline == start + 30 + 3600)
}

@Test func anEndRemovesTheActivityAndSendsNothingBack() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    #expect(reduce(&state, .activityEnded(activity().key), now: start).isEmpty)
    #expect(state.activities.items.isEmpty)
    // Ending one that's gone is no mistake: the user may have closed it first.
    #expect(reduce(&state, .activityEnded(activity().key), now: start).isEmpty)
}

@Test func aClosedConnectionTakesEverythingItStartedAndNothingElse() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", client: 1)), now: start)
    _ = reduce(&state, .activityStarted(activity("b", client: 1)), now: start)
    _ = reduce(&state, .activityStarted(activity("c", client: 2)), now: start)
    #expect(reduce(&state, .activityClientClosed(client: 1), now: start).isEmpty)
    #expect(state.activities.items.map(\.key.id) == ["c"])
}

// MARK: The user

@Test func aButtonPressAsksForAHapticAndTellsTheSender() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    let effects = reduce(&state, .activityButton(activity().key, button: "stop"), now: start)
    #expect(effects == [.haptic, .sendActivityEvent(activity().key, .button("stop"))])
    // Warble doesn't guess what the button does: the activity stays until the sender answers.
    #expect(state.activities.items.count == 1)
}

@Test func aPressOnAButtonThatDoesntExistGoesNowhere() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    #expect(reduce(&state, .activityButton(activity().key, button: "pause"), now: start).isEmpty)
}

@Test func aPressOnAnActivityThatClosedWithItsConnectionGoesNowhere() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    _ = reduce(&state, .activityClientClosed(client: 1), now: start)
    #expect(reduce(&state, .activityButton(activity().key, button: "stop"), now: start).isEmpty)
}

@Test func aPressChangesNoDeadline() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity(lasts: 60)), now: start)
    _ = reduce(&state, .activityButton(activity().key, button: "stop"), now: start + 10)
    #expect(state.deadline == start + 60)
}

@Test func dismissingAnActivityEndsItAndTellsTheSender() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a")), now: start)
    _ = reduce(&state, .activityStarted(activity("b")), now: start)
    #expect(reduce(&state, .activityDismissed(activity("a").key), now: start) == [ending(activity("a").key, .dismissed)])
    #expect(state.activities.items.map(\.key.id) == ["b"])
    // The row may still be on screen as it goes, so a second dismissal says nothing.
    #expect(reduce(&state, .activityDismissed(activity("a").key), now: start).isEmpty)
}

@Test func blockingAnAppEndsItsActivitiesAsBlockedAndLeavesTheRest() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", client: 1)), now: start)
    _ = reduce(&state, .activityStarted(activity("b", client: 2, owner: backup)), now: start)
    _ = reduce(&state, .activityStarted(activity("c", client: 1)), now: start)
    let effects = reduce(&state, .activityBlocklistChanged([shot.identifier]), now: start)
    #expect(effects == [ending(activity("a", client: 1).key, .blocked), ending(activity("c", client: 1).key, .blocked)])
    #expect(state.activities.items.map(\.key.id) == ["b"])
}

@Test func turningAnAppBackOnLetsItStartAgain() {
    var state = on()
    _ = reduce(&state, .activityBlocklistChanged([shot.identifier]), now: start)
    _ = reduce(&state, .activityBlocklistChanged([]), now: start)
    _ = reduce(&state, .activityStarted(activity()), now: start)
    #expect(state.activities.items.count == 1)
}

// MARK: The deadline

@Test func withNothingLiveNothingIsDue() {
    var state = on()
    #expect(state.deadline == nil)
    _ = reduce(&state, .activityStarted(activity()), now: start)
    _ = reduce(&state, .activityEnded(activity().key), now: start)
    #expect(state.deadline == nil)
}

@Test func theDeadlineIsTheEarliestEndOfTheActivitiesLive() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", lasts: 600)), now: start)
    _ = reduce(&state, .activityStarted(activity("b", lasts: 60)), now: start)
    _ = reduce(&state, .activityStarted(activity("c", client: 2, lasts: 1200)), now: start)
    #expect(state.deadline == start + 60)
    _ = reduce(&state, .activityEnded(activity("b").key), now: start)
    #expect(state.deadline == start + 600)
}

@Test func aTickRemovesTheActivitiesPastTheirEndAndTellsEachSender() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", lasts: 60)), now: start)
    _ = reduce(&state, .activityStarted(activity("b", lasts: 600)), now: start)
    _ = reduce(&state, .activityStarted(activity("c", client: 2, lasts: 60)), now: start)
    #expect(reduce(&state, .tick, now: start + 59).isEmpty)
    let effects = reduce(&state, .tick, now: start + 60)
    #expect(effects == [ending(activity("a").key, .expired), ending(activity("c", client: 2).key, .expired)])
    #expect(state.activities.items.map(\.key.id) == ["b"])
    #expect(state.deadline == start + 600)
}

@Test func anActivityLastsAnHourUnlessItAsksForLess() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity()), now: start)
    #expect(state.deadline == start + 3600)
}

@Test func theRankingPutsHighFirstThenTheNewest() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a")), now: start)
    _ = reduce(&state, .activityStarted(activity("b", priority: .high)), now: start)
    _ = reduce(&state, .activityStarted(activity("c", client: 2)), now: start)
    #expect(state.activities.ranked.map(\.key.id) == ["b", "c", "a"])
    #expect(state.activities.current?.key.id == "b")
    _ = reduce(&state, .activityEnded(activity("b").key), now: start)
    #expect(state.activities.current?.key.id == "c")
}

@Test func theNewestOfTwoHighActivitiesWinsTheWings() {
    var state = on()
    _ = reduce(&state, .activityStarted(activity("a", priority: .high)), now: start)
    _ = reduce(&state, .activityStarted(activity("b", priority: .high)), now: start)
    #expect(state.activities.current?.key.id == "b")
}
