import Foundation
import Testing
@testable import WarbleModel

private let start = activityStart

private let app = ActivitySender(client: 1, identifier: "TEAM.dev.shot", name: "Shot", bundleIdentifier: "dev.shot")
private let script = ActivitySender(client: 2, identifier: "/usr/bin/python3", name: "python3")

@MainActor
private final class Rig {
    let store: Store
    let clock = FakeClock(start)
    let handler: ActivityHandler
    private(set) var dispatched: [AppAction] = []

    init(on: Bool = true) {
        let store = Store(state: AppState(showsActivities: on), clock: clock, scheduler: FakeScheduler())
        self.store = store
        let clock = clock
        var record: ((AppAction) -> Void)?
        handler = ActivityHandler(state: { store.state }, dispatch: { record?($0) }, clock: clock)
        record = { [weak self] action in
            self?.dispatched.append(action)
            store.dispatch(action)
        }
    }

    func send(_ json: String, from sender: ActivitySender = app) -> ActivityReply {
        handler.handle(Data(json.utf8), from: sender)
    }

    var items: [Activity] { store.state.activities.items }
}

private func start(_ id: String, title: String = "Recording") -> String {
    #"{"v":1,"op":"start","id":"\#(id)","title":"\#(title)"}"#
}

@MainActor
@Test func aStartShowsAtOnceAndIsAnsweredOk() {
    let rig = Rig()
    let reply = rig.send(#"{"v":1,"op":"start","id":"recording","title":"Recording","lasts":120,"buttons":[{"id":"stop","label":"Stop"}]}"#)
    #expect(reply == .success("start"))
    let item = rig.items.first
    #expect(item?.key == ActivityKey(client: 1, id: "recording"))
    #expect(item?.owner == ActivityOwner(identifier: "TEAM.dev.shot", name: "Shot", bundleIdentifier: "dev.shot"))
    #expect(item?.endsAt == start + 120)
    #expect(item?.buttons == [ActivityButton(id: "stop", label: "Stop")])
}

@MainActor
@Test func theReplyIsOneSortedLine() {
    #expect(String(decoding: ActivityReply.success("start").line, as: UTF8.self) == #"{"ok":true,"re":"start","v":1}"# + "\n")
    #expect(String(decoding: ActivityReply.failure(ActivityError("title is missing", operation: "start")).line, as: UTF8.self)
        == #"{"error":"title is missing","ok":false,"re":"start","v":1}"# + "\n")
}

@MainActor
@Test func aRefusedLineIsAnsweredWithTheSentenceAndChangesNothing() {
    let rig = Rig()
    let reply = rig.send(#"{"v":1,"op":"start","id":"a","title":"\#(String(repeating: "t", count: 74))"}"#)
    #expect(reply == ActivityReply(re: "start", ok: false, error: "title is 74 characters; the most is 60"))
    #expect(rig.dispatched.isEmpty)
}

@MainActor
@Test func aLineThatIsntUnderstoodIsAnsweredWithoutAnOp() {
    let reply = Rig().send("nonsense")
    #expect(reply.ok == false && reply.re == nil)
}

@MainActor
@Test func anUpdateAndAnEndDispatchWhatTheNotchWouldDo() {
    let rig = Rig()
    _ = rig.send(start("a"))
    #expect(rig.send(#"{"v":1,"op":"update","id":"a","detail":"Paused"}"#) == .success("update"))
    #expect(rig.items.first?.detail == "Paused")
    #expect(rig.send(#"{"v":1,"op":"end","id":"a"}"#) == .success("end"))
    #expect(rig.items.isEmpty)
}

@MainActor
@Test func anUpdateForAnActivityThatsGoneIsAnsweredWithAnError() {
    let reply = Rig().send(#"{"v":1,"op":"update","id":"a","detail":"Paused"}"#)
    #expect(reply.error == #"there's no activity with the id "a"; it may have ended or been closed"#)
    #expect(reply.re == "update")
}

@MainActor
@Test func endingAnActivityThatsGoneIsNotAMistake() {
    #expect(Rig().send(#"{"v":1,"op":"end","id":"a"}"#) == .success("end"))
}

@MainActor
@Test func aConnectionHasTwoActivitiesAtOnce() {
    let rig = Rig()
    #expect(rig.send(start("a")).ok)
    #expect(rig.send(start("b")).ok)
    let third = rig.send(start("c"))
    #expect(third.error == "a connection can have 2 activities at once")
    #expect(third.re == "start")
    // Starting one with an id in use is a replacement, not a third.
    #expect(rig.send(start("b", title: "Again")).ok)
    #expect(rig.items.map(\.title) == ["Recording", "Again"])
}

@MainActor
@Test func threeActivitiesShowAtOnceAcrossConnections() {
    let rig = Rig()
    #expect(rig.send(start("a"), from: app).ok)
    #expect(rig.send(start("b"), from: app).ok)
    #expect(rig.send(start("c"), from: ActivitySender(client: 3, identifier: "T.other", name: "Other", bundleIdentifier: "other")).ok)
    #expect(rig.send(start("d"), from: ActivitySender(client: 4, identifier: "T.third", name: "Third", bundleIdentifier: "third")).error == "Warble can show 3 activities at once")
}

@MainActor
@Test func aSenderTurnedOffInSettingsIsRefusedByName() {
    let rig = Rig()
    rig.store.dispatch(.activityBlocklistChanged(["TEAM.dev.shot"]))
    #expect(rig.send(start("a")).error == "Shot is turned off in Settings › Activities")
}

@MainActor
@Test func withActivitiesOffAStartIsRefused() {
    #expect(Rig(on: false).send(start("a")).error == "Warble isn't showing activities; they're off in Settings")
}

@MainActor
@Test func aScriptMustNameItselfAndShowsAsScriptFrom() {
    let rig = Rig()
    #expect(rig.send(start("a"), from: script).error == "from is missing; a script names itself with from")
    #expect(rig.send(#"{"v":1,"op":"start","id":"a","title":"Backing up","from":"backup"}"#, from: script).ok)
    let owner = rig.items.first?.owner
    #expect(owner?.name == "backup")
    #expect(owner?.label == "Script: backup")
    #expect(owner?.isScript == true)
}

@MainActor
@Test func twoScriptsOnTheSameInterpreterAreBlockedSeparately() {
    let rig = Rig()
    let first = rig.send(#"{"v":1,"op":"start","id":"a","title":"One","from":"backup"}"#, from: script)
    let other = ActivitySender(client: 3, identifier: "/usr/bin/python3", name: "python3")
    let second = rig.send(#"{"v":1,"op":"start","id":"a","title":"Two","from":"sync"}"#, from: other)
    #expect(first.ok && second.ok)
    let identifiers = rig.items.map(\.owner.identifier)
    #expect(Set(identifiers).count == 2)
    rig.store.dispatch(.activityBlocklistChanged([identifiers[0]]))
    #expect(rig.items.map(\.title) == ["Two"])
}

@MainActor
@Test func aSignedAppCantTakeAnotherNameWithFrom() {
    let rig = Rig()
    #expect(rig.send(#"{"v":1,"op":"start","id":"a","title":"T","from":"Safari"}"#).ok)
    #expect(rig.items.first?.owner.name == "Shot")
    #expect(rig.items.first?.owner.isScript == false)
}

@MainActor
@Test func aConnectionMayTwentyLinesASecondAndIsToldToSlowDownAfter() {
    let rig = Rig()
    for _ in 0..<20 {
        #expect(rig.send(#"{"v":1,"op":"end","id":"a"}"#).ok)
    }
    #expect(rig.send(#"{"v":1,"op":"end","id":"a"}"#).error == "slow down; a connection may send 20 lines a second")
    // Counted from each line's arrival, so a second later it's allowed again.
    rig.clock.now += 1
    #expect(rig.send(#"{"v":1,"op":"end","id":"a"}"#).ok)
}

@MainActor
@Test func theRateIsPerConnection() {
    let rig = Rig()
    for _ in 0..<21 {
        _ = rig.send(#"{"v":1,"op":"end","id":"a"}"#)
    }
    #expect(rig.send(#"{"v":1,"op":"end","id":"a"}"#, from: ActivitySender(client: 9, identifier: "T.x", name: "X", bundleIdentifier: "x")).ok)
}

@MainActor
@Test func aSlowedDownLineChangesNothing() {
    let rig = Rig()
    for _ in 0..<20 {
        _ = rig.send(#"{"v":1,"op":"end","id":"a"}"#)
    }
    #expect(!rig.send(start("a")).ok)
    #expect(rig.items.isEmpty)
}

@MainActor
@Test func aClosedConnectionEndsItsActivitiesAndStartsItsRateOver() {
    let rig = Rig()
    _ = rig.send(start("a"))
    for _ in 0..<19 {
        _ = rig.send(#"{"v":1,"op":"end","id":"b"}"#)
    }
    rig.handler.closed(client: 1)
    #expect(rig.items.isEmpty)
    #expect(rig.dispatched.last == .activityClientClosed(client: 1))
    // The next connection to get number 1 isn't counted with the one before it.
    for _ in 0..<20 {
        #expect(rig.send(#"{"v":1,"op":"end","id":"b"}"#).ok)
    }
}
