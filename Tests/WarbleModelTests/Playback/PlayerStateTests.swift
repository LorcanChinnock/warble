import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: 1, shuffle: .off, repeatMode: .off)

private struct Run {
    var state = AppState()
    var effects: [AppEffect] = []
    var now = start

    init(playing: PlaybackState? = song) {
        send(.housingsChanged([notch]))
        if let playing {
            send(.playbackReported(playing))
        }
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }
}

// MARK: Optimistic commands

@Test func playPauseShowsAtOnceAndIsSent() {
    var run = Run()
    run.send(.command(.togglePlayPause), after: 5)
    #expect(run.state.playback?.isPlaying == false)
    #expect(run.state.playback?.elapsed == 15)
    #expect(run.effects.contains(.send(.togglePlayPause)))
    run.send(.command(.play))
    #expect(run.state.playback?.isPlaying == true)
}

@Test func seekShuffleAndRepeatShowAtOnce() {
    var run = Run()
    run.send(.command(.seek(to: 100)))
    #expect(run.state.playback?.elapsed == 100)
    run.send(.command(.setShuffle(.songs)))
    run.send(.command(.setRepeat(.all)))
    #expect(run.state.playback?.shuffle == .songs)
    #expect(run.state.playback?.repeatMode == .all)
    #expect(run.effects == [.send(.seek(to: 100)), .send(.setShuffle(.songs)), .send(.setRepeat(.all))])
}

@Test func skippingWaitsForTheApp() {
    var run = Run()
    run.send(.command(.nextTrack))
    #expect(run.state.playback == song)
    #expect(run.effects == [.send(.nextTrack)])
}

@Test func nothingIsGuessedWhileAHideIsPending() {
    var run = Run()
    run.send(.playbackReported(nil))
    run.send(.command(.togglePlayPause))
    #expect(run.state.playback == song)
    #expect(run.state.hideAt != nil)
    #expect(run.effects == [.send(.togglePlayPause)])
}

@Test func openAppOpensTheOneThatsPlaying() {
    var run = Run()
    run.send(.openApp)
    #expect(run.effects == [.openApp(bundleIdentifier: "com.apple.Music")])
    var idle = Run(playing: nil)
    idle.send(.openApp)
    #expect(idle.effects.isEmpty)
}

// MARK: Volume and outputs

@Test func theVolumeIsFollowedOnlyWhileThePlayersCardIsOpen() {
    var run = Run()
    run.send(.hover(display: "built-in", .click))
    #expect(run.effects.contains(.followVolume(true)))
    run.send(.dismiss(except: nil))
    #expect(run.effects.last == .followVolume(false))
}

@Test func aScrollChangesTheVolumeFromWhatItIsNowWithATickAtEachTenth() {
    var run = Run()
    let crossing = VolumeScroll.volume(after: 1, from: 0.58, precise: false, inverted: false)
    #expect(VolumeScroll.crossesTick(from: 0.58, to: crossing))
    run.send(.scrolled(delta: 1, precise: false, inverted: false, volume: 0.58, isMuted: false))
    #expect(run.effects == [.setVolume(crossing), .haptic])
    run.effects = []
    let within = VolumeScroll.volume(after: 1, from: 0.61, precise: false, inverted: false)
    #expect(!VolumeScroll.crossesTick(from: 0.61, to: within))
    run.send(.scrolled(delta: 1, precise: false, inverted: false, volume: 0.61, isMuted: false))
    #expect(run.effects == [.setVolume(within)])
}

@Test func aScrollDoesNothingWithoutAVolumeOrADelta() {
    var run = Run()
    run.send(.scrolled(delta: 1, precise: false, inverted: false, volume: nil, isMuted: false))
    run.send(.scrolled(delta: 0, precise: false, inverted: false, volume: 0.5, isMuted: false))
    #expect(run.effects.isEmpty)
}

@Test func aMutedOutputScrollsUpFromSilence() {
    var run = Run()
    run.send(.scrolled(delta: 1, precise: false, inverted: false, volume: 0.8, isMuted: true))
    #expect(run.effects.first == .setVolume(VolumeScroll.wheelStep))
}

@Test func theSliderAndOutputMenuAskForTheirChanges() {
    var run = Run()
    run.send(.setVolume(0.3))
    run.send(.selectOutput(2))
    #expect(run.effects == [.setVolume(0.3), .selectOutput(2)])
    run.send(.volumeRead(0.3, isMuted: false))
    run.send(.outputsRead([], current: 2))
    #expect(run.state.volume == 0.3)
    #expect(run.state.currentOutput == 2)
}

@MainActor
@Test func theRunnerListensToTheVolumeOnlyWhileFollowingAndReadsChanges() {
    let volume = FakeVolume()
    let outputs = FakeOutputs()
    let runner = makeRunner(volume: volume, outputs: outputs)
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.perform(.followVolume(true))
    #expect(volume.listening && outputs.listening)
    #expect(dispatched == [.volumeRead(0.5, isMuted: false), .outputsRead(outputs.all, current: 1)])
    volume.change(to: 0.7)
    #expect(dispatched.last == .volumeRead(0.7, isMuted: false))
    runner.perform(.followVolume(false))
    #expect(!volume.listening && !outputs.listening)
}

@MainActor
@Test func theRunnerSetsTheVolumeAndOutputAndReadsThemBack() {
    let volume = FakeVolume()
    let outputs = FakeOutputs()
    let runner = makeRunner(volume: volume, outputs: outputs)
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.perform(.setVolume(0.2))
    runner.perform(.selectOutput(2))
    #expect(volume.volume == 0.2)
    #expect(dispatched == [.volumeRead(0.2, isMuted: false), .outputsRead(outputs.all, current: 2)])
}
