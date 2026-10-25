import Foundation
import Testing
@testable import WarbleModel

private let start = activityStart

private func line(_ event: ActivityEvent, id: String = "recording") -> String {
    String(decoding: event.line(id: id), as: UTF8.self)
}

@Test func aButtonEventIsOneLineWithTheButtonsID() {
    #expect(line(.button("stop")) == #"{"button":"stop","event":"button","id":"recording","v":1}"# + "\n")
}

@Test func anEndedEventNamesWhyItEnded() {
    #expect(line(.ended(.dismissed)) == #"{"event":"ended","id":"recording","reason":"dismissed","v":1}"# + "\n")
    #expect(line(.ended(.expired)).contains(#""reason":"expired""#))
    #expect(line(.ended(.blocked)).contains(#""reason":"blocked""#))
}

@Test func anIDWithQuotesAndNewlinesCantBreakTheLine() {
    let text = line(.button("a\"b"), id: "x\ny")
    #expect(text.filter { $0 == "\n" }.count == 1)
    #expect(text.hasSuffix("\n"))
}

@MainActor
@Test func aButtonPressReachesOnlyTheConnectionThatStartedTheActivity() {
    let channel = FakeActivityChannel(open: [1, 2])
    let runner = makeRunner(activityChannel: channel)
    runner.perform(.sendActivityEvent(ActivityKey(client: 2, id: "recording"), .button("stop")))
    #expect(channel.lines(to: 1).isEmpty)
    #expect(channel.lines(to: 2) == [line(.button("stop"))])
}

@MainActor
@Test func aPressForAConnectionThatHasClosedIsDroppedNotSentElsewhere() {
    let channel = FakeActivityChannel(open: [1])
    let runner = makeRunner(activityChannel: channel)
    runner.perform(.sendActivityEvent(ActivityKey(client: 2, id: "recording"), .button("stop")))
    #expect(channel.delivered.isEmpty)
    #expect(channel.dropped == 1)
}

@MainActor
@Test func withNoSocketAnEventGoesNowhereAndNothingBreaks() {
    makeRunner().perform(.sendActivityEvent(ActivityKey(client: 1, id: "recording"), .ended(.expired)))
}

@MainActor
@Test func theSocketEffectsAreLeftToThePlatform() {
    let runner = makeRunner()
    var platform: [AppEffect] = []
    runner.platform = { platform.append($0) }
    runner.perform(.listenForActivities(true))
    runner.perform(.saveActivityApps(["a": "A"]))
    #expect(platform == [.listenForActivities(true), .saveActivityApps(["a": "A"])])
}

/// A press and an expiry, from the action to the connection, through the store and the runner as the app has them.
@MainActor
@Test func aPressAndAnExpiryTravelFromTheStoreToTheConnection() {
    let channel = FakeActivityChannel(open: [1])
    let runner = makeRunner(activityChannel: channel)
    let scheduler = FakeScheduler()
    let store = Store(state: AppState(showsActivities: true), clock: FakeClock(start), scheduler: scheduler)
    store.perform = { runner.perform($0) }
    store.dispatch(.activityStarted(activity(lasts: 60)))
    #expect(scheduler.deadline == start + 60)
    store.dispatch(.activityButton(activity().key, button: "stop"))
    #expect(channel.lines(to: 1) == [line(.button("stop"))])
    store.dispatch(.activityClientClosed(client: 1))
    channel.open = []
    store.dispatch(.activityButton(activity().key, button: "stop"))
    #expect(channel.dropped == 0)
    #expect(scheduler.deadline == nil)
}

@MainActor
@Test func theStoreArmsNoTimerForActivitiesUntilOneStarts() {
    let scheduler = FakeScheduler()
    let store = Store(state: AppState(showsActivities: true), clock: FakeClock(start), scheduler: scheduler)
    store.dispatch(.launched(firstRun: false))
    #expect(scheduler.deadline == nil)
    #expect(scheduler.armed == 0)
    store.dispatch(.activityStarted(activity()))
    #expect(scheduler.armed == 1)
    store.dispatch(.activityEnded(activity().key))
    #expect(scheduler.deadline == nil)
}
