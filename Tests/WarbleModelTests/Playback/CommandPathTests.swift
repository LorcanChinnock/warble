import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: start, rate: 1)

private func playing() -> AppState {
    var state = AppState()
    _ = reduce(&state, .playbackReported(song), now: start)
    return state
}

@MainActor
@Test func theRunnerSendsCommandsToTheSource() async {
    let source = FakeSource()
    let runner = makeRunner()
    runner.source = source
    runner.perform(.send(.nextTrack))
    // The send runs on its own task; give it a turn.
    for _ in 0..<100 where await source.sent.isEmpty {
        await Task.yield()
    }
    #expect(await source.sent == [.nextTrack])
}

