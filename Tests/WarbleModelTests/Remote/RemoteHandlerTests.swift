import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: 1)

@MainActor
private final class Rig {
    let store: Store
    let volume: FakeVolume
    let outputs: FakeOutputs
    let handler: RemoteHandler
    /// What the handler dispatched, which the store also took.
    private let log = ActionLog()
    var dispatched: [AppAction] { log.actions }

    final class ActionLog {
        var actions: [AppAction] = []
    }

    init(playing: PlaybackState? = nil) {
        let store = Store(state: AppState(), clock: FakeClock(start), scheduler: FakeScheduler())
        self.store = store
        let volume = FakeVolume()
        let outputs = FakeOutputs()
        self.volume = volume
        self.outputs = outputs
        if let playing {
            store.dispatch(.playbackReported(playing))
        }
        let log = log
        handler = RemoteHandler(
            state: { store.state }, dispatch: { log.actions.append($0); store.dispatch($0) }, volume: volume, outputs: outputs,
            clock: FakeClock(start)
        )
    }

    func ask(_ arguments: String...) -> RemoteResponse {
        handler.handle(RemoteRequest(arguments: arguments))
    }
}

@MainActor
@Test func nowAnswersWithWhatsPlaying() throws {
    let rig = Rig(playing: song)
    let now = try #require(try rig.ask("now").result())
    #expect(now.status == .playing)
    #expect(now.title == "Song")
    #expect(now.volume == 50)
    #expect(rig.dispatched.isEmpty)
}

@MainActor
@Test func nowWithNothingPlayingSaysStopped() throws {
    let rig = Rig()
    #expect(try rig.ask("now").result()?.status == .stopped)
}

@MainActor
@Test func eachCommandDispatchesTheActionItsButtonDoes() {
    let rig = Rig(playing: song)
    for (arguments, action) in [
        (["toggle"], AppAction.perform(.playPause)), (["play"], .command(.play)), (["pause"], .command(.pause)),
        (["next"], .perform(.nextTrack)), (["previous"], .perform(.previousTrack)), (["seek", "60"], .command(.seek(to: 60))),
        (["volume", "25"], .setVolume(0.25)),
    ] {
        let before = rig.dispatched.count
        #expect(rig.handler.handle(RemoteRequest(arguments: arguments)).ok)
        #expect(rig.dispatched.dropFirst(before) == [action])
    }
}

@MainActor
@Test func aCommandShowsItsGuessAtOnce() {
    let rig = Rig(playing: song)
    #expect(rig.ask("pause").ok)
    #expect(rig.store.state.playback?.isPlaying == false)
}

@MainActor
@Test func anOutputIsPickedByName() {
    let rig = Rig()
    #expect(rig.ask("output", "airpods").ok)
    #expect(rig.dispatched == [.selectOutput(2)])
    #expect(rig.ask("output", "MacBook").ok)
    #expect(rig.dispatched.last == .selectOutput(1))
}

@MainActor
@Test func anUnknownOutputIsAnErrorThatListsTheOutputs() {
    let rig = Rig()
    let response = rig.ask("output", "Headphones")
    #expect(!response.ok)
    #expect(response.code == 64)
    #expect(response.error == "no single output matches \"Headphones\"; the outputs are MacBook Air Speakers, AirPods")
    #expect(rig.dispatched.isEmpty)
}

@MainActor
@Test func withNoOutputsThereIsNothingToPick() {
    let rig = Rig()
    rig.outputs.all = []
    #expect(rig.ask("output", "AirPods").error == "no sound outputs are available")
}

@MainActor
@Test func aVolumeNeedsAnOutputThatHasOne() {
    let rig = Rig()
    rig.volume.volume = nil
    let response = rig.ask("volume", "30")
    #expect(!response.ok)
    #expect(response.code == 69)
    #expect(rig.dispatched.isEmpty)
}

@MainActor
@Test func badInputGetsItsUsageErrorBack() throws {
    let rig = Rig()
    let response = rig.ask("seek", "soon")
    #expect(response.code == 64)
    #expect(throws: RemoteCommandError.self) { try response.result() }
    #expect(rig.ask("dance").error == "no command named \"dance\"")
    #expect(rig.dispatched.isEmpty)
}

@MainActor
@Test func aRequestOfAnotherVersionIsRefused() {
    #expect(throws: RemoteCommandError.self) { try RemoteRequest.decode(Data(#"{"v":2,"arguments":["now"]}"#.utf8)) }
}

@MainActor
@Test func commandsWithNothingPlayingSetNoTimer() {
    let rig = Rig()
    for arguments in [["toggle"], ["next"], ["seek", "30"], ["now"]] {
        #expect(rig.handler.handle(RemoteRequest(arguments: arguments)).ok)
    }
    #expect(rig.store.state.deadline == nil)
}

@Test func aRequestAndItsResponseRoundTripAsOneLine() throws {
    let request = RemoteRequest(arguments: ["output", "MacBook Pro"])
    #expect(request.line.last == UInt8(ascii: "\n"))
    #expect(try RemoteRequest.decode(request.line.dropLast()) == request)
    for response in [RemoteResponse.success(), .failure(.unavailable("off"))] {
        #expect(response.line.filter { $0 == UInt8(ascii: "\n") }.count == 1)
        #expect(try RemoteResponse.decode(response.line.dropLast()) == response)
    }
    #expect(throws: RemoteCommandError.self) { try RemoteResponse.decode(Data("nonsense".utf8)) }
    #expect(throws: RemoteCommandError.self) { try RemoteRequest.decode(Data("[1]".utf8)) }
}
