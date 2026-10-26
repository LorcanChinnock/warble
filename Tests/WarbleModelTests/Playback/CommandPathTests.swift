import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", elapsedTimestamp: start, rate: 1)

private func playing() -> AppState {
    var state = AppState()
    _ = reduce(&state, .sourceReported(bundleIdentifier: "app", song), now: start)
    return state
}

@Test func aShortcutDoesWhatTheSameButtonDoes() {
    var shortcut = playing()
    var button = playing()
    let fromShortcut = reduce(&shortcut, .perform(.playPause), now: start + 1)
    let fromButton = reduce(&button, .command(.togglePlayPause), now: start + 1)
    #expect(shortcut == button)
    #expect(fromShortcut == fromButton)
    #expect(fromShortcut == [.send(.togglePlayPause)])
}

@Test func everyActionWithACommandSendsIt() {
    for action in WarbleAction.allCases {
        var state = playing()
        let effects = reduce(&state, .perform(action), now: start)
        if let command = action.command {
            #expect(effects == [.send(command)])
        } else {
            #expect(effects == [.toggleKeyboard])
        }
    }
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

@MainActor
@Test func theRunnerHandsTheKeyboardToThePlatform() {
    let runner = makeRunner()
    var handed: [AppEffect] = []
    runner.platform = { handed.append($0) }
    runner.perform(.toggleKeyboard)
    #expect(handed == [.toggleKeyboard])
}
