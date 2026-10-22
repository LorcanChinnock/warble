import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let song = PlaybackState(
    bundleIdentifier: "com.apple.Music", title: "Amazing Grace", artist: "Traditional", album: "Hymns", duration: 200,
    elapsed: 0, elapsedTimestamp: start, rate: 1
)
/// Public domain: John Newton, 1779.
private let lrc = """
[00:05.00] Amazing grace, how sweet the sound
[00:10.00] That saved a wretch like me
[00:15.00]
[00:20.00] I once was lost, but now am found
"""
private let grace = Lyrics(lrc: lrc)!

private func next(_ title: String = "Next") -> PlaybackState {
    var next = song
    next.title = title
    return next
}

private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(lyrics: Bool = true, playing: PlaybackState? = nil) {
        state = AppState(showsLyrics: lyrics)
        send(.housingsChanged([notch]))
        if let playing {
            send(.playbackReported(playing))
        }
    }

    /// `.tick` at `seconds` since the start, as `Store` sends it at the deadline.
    mutating func send(_ action: AppAction, at seconds: TimeInterval? = nil) {
        if let seconds {
            now = start + seconds
        }
        effects += reduce(&state, action, now: now)
    }

    var fetches: [AppEffect] {
        effects.filter { if case .fetchLyrics = $0 { true } else { false } }
    }

    var line: String? { state.lyrics.line?.text }
}

// MARK: Fetching

@Test func withLyricsOffANewTrackAsksForNoFetch() {
    var run = Run(lyrics: false, playing: song)
    run.send(.playbackReported(next()), at: 1)
    #expect(run.fetches.isEmpty)
    #expect(run.state.lyrics.deadline == nil)
}

@Test func withLyricsOnANewTrackAsksForOneFetch() {
    let run = Run(playing: song)
    #expect(run.fetches == [.fetchLyrics(LyricsQuery(artist: "Traditional", title: "Amazing Grace", album: "Hymns", duration: 200), pass: 1)])
}

@Test func aPauseASeekOrNewArtAsksForNoFetch() {
    var run = Run(playing: song)
    run.send(.playbackReported(song.playing(false, at: start + 3)), at: 3)
    run.send(.playbackReported(song.seeked(to: 50, at: start + 4)), at: 4)
    var withArt = song.seeked(to: 50, at: start + 4)
    withArt.artwork = Data([1, 2, 3])
    run.send(.playbackReported(withArt), at: 5)
    run.send(.command(.togglePlayPause), at: 6)
    #expect(run.fetches.count == 1)
}

@Test func eachNewTrackAsksAgainWithTheNextPass() {
    var run = Run(playing: song)
    run.send(.playbackReported(next()), at: 1)
    #expect(run.fetches.last == .fetchLyrics(LyricsQuery(next())!, pass: 2))
}

@Test func aTrackThatStartsPausedIsFetchedOnlyOnceItPlays() {
    var run = Run(playing: song.playing(false, at: start))
    #expect(run.fetches.isEmpty)
    run.send(.command(.play), at: 1)
    #expect(run.fetches.count == 1)
}

@Test func aPodcastOrASourceWithoutALengthAsksForNothing() {
    var podcast = song
    podcast.bundleIdentifier = "com.apple.podcasts"
    var stream = song
    stream.duration = nil
    let runs = [Run(playing: podcast), Run(playing: stream)]
    #expect(runs.allSatisfy { $0.fetches.isEmpty && $0.state.notchState("built-in") == .resting })
}

@Test func turningLyricsOnFetchesWhatsPlayingAndOffDropsTheAnswer() {
    var run = Run(lyrics: false, playing: song)
    run.send(.lyricsChanged(true), at: 1)
    #expect(run.fetches.count == 1)
    run.send(.lyricsChanged(false), at: 2)
    run.send(.lyricsLoaded(grace, pass: 1), at: 3)
    #expect(run.state.lyrics.lyrics == nil)
    #expect(run.line == nil)
    #expect(run.state.deadline == nil)
}

@Test func anAnswerForAnOlderTrackIsDropped() {
    var run = Run(playing: song)
    run.send(.playbackReported(next()), at: 1)
    run.send(.lyricsLoaded(grace, pass: 1), at: 6)
    #expect(run.state.lyrics.lyrics == nil)
    #expect(run.state.notchState("built-in") == .resting)
    run.send(.lyricsLoaded(grace, pass: 2), at: 6)
    #expect(run.line == "Amazing grace, how sweet the sound")
}

// MARK: The line

@Test func theLineMovesOnAtEachLinesTimeThroughTick() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(grace, pass: 1), at: 1)
    #expect(run.line == nil)
    #expect(run.state.deadline == start + 5)
    run.send(.tick, at: 5)
    #expect(run.line == "Amazing grace, how sweet the sound")
    #expect(run.state.notchState("built-in") == .lyrics)
    #expect(run.state.deadline == start + 10)
    run.send(.tick, at: 10)
    #expect(run.line == "That saved a wretch like me")
    run.send(.tick, at: 15)
    // A gap: the strip goes until the next line.
    #expect(run.state.notchState("built-in") == .resting)
    #expect(run.state.deadline == start + 20)
    run.send(.tick, at: 20)
    #expect(run.line == "I once was lost, but now am found")
    // After the last line nothing more is due.
    #expect(run.state.lyrics.deadline == nil)
}

@Test func aSeekMovesTheLineAtOnce() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(grace, pass: 1), at: 6)
    run.send(.command(.seek(to: 21)), at: 7)
    #expect(run.line == "I once was lost, but now am found")
    run.send(.playbackReported(song.seeked(to: 11, at: start + 8)), at: 8)
    #expect(run.line == "That saved a wretch like me")
    #expect(run.state.deadline == start + 12)
}

@Test func atDoubleSpeedTheNextLineIsDueSooner() {
    var fast = song
    fast.rate = 2
    var run = Run(playing: fast)
    run.send(.lyricsLoaded(grace, pass: 1))
    #expect(run.state.deadline == start + 2.5)
    run.send(.tick, at: 2.5)
    #expect(run.line == "Amazing grace, how sweet the sound")
}

@Test func pausedThereIsNoLyricsDeadlineAndNoLine() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(grace, pass: 1), at: 6)
    run.send(.playbackReported(song.playing(false, at: start + 7)), at: 7)
    #expect(run.line == nil)
    #expect(run.state.lyrics.deadline == nil)
    #expect(run.state.notchState("built-in") == .resting)
    run.send(.playbackReported(song.seeked(to: 7, at: start + 9).playing(true, at: start + 9)), at: 9)
    #expect(run.line == "Amazing grace, how sweet the sound")
    #expect(run.fetches.count == 1)
}

@Test func withNoLyricsFoundNothingShowsAndNothingIsDue() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(nil, pass: 1), at: 6)
    #expect(run.line == nil)
    #expect(run.state.deadline == nil)
    #expect(run.state.notchState("built-in") == .resting)
}

@Test func aNewTrackHidesTheOldTracksLineUntilItsOwnArrive() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(grace, pass: 1), at: 6)
    run.send(.playbackReported(next()), at: 7)
    #expect(run.line == nil)
    #expect(run.state.lyrics.deadline == nil)
}

@Test func idleShowsNoLineAndKeepsNoDeadline() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(grace, pass: 1), at: 6)
    run.send(.playbackReported(nil), at: 7)
    run.send(.tick, at: 7 + AppState.hideDelay)
    #expect(!run.state.showsPlayback)
    #expect(run.line == nil)
    #expect(run.state.deadline == nil)
}

@Test func anOpenNotchDrawsTheCardNotTheStrip() {
    var run = Run(playing: song)
    run.send(.lyricsLoaded(grace, pass: 1), at: 6)
    run.send(.hover(display: "built-in", .click), at: 6)
    #expect(run.state.notchState("built-in") == .expanded)
}

@Test func theTrackChangeToastTakesTheStripAndTheLineShowsAgainOnceItGoes() {
    var run = Run(playing: song)
    run.state.showsTrackToast = true
    run.send(.playbackReported(next().seeked(to: 6, at: start + 1)), at: 1)
    run.send(.lyricsLoaded(grace, pass: 2), at: 1.5)
    #expect(run.line == "Amazing grace, how sweet the sound")
    #expect(run.state.notchState("built-in") == .toast)
    #expect(run.state.deadline == start + 1 + TrackToast.duration)
    run.send(.tick, at: 1 + TrackToast.duration)
    #expect(run.state.toasts.current == nil)
    #expect(run.state.notchState("built-in") == .lyrics)
}

// MARK: Nothing playing

@Test func withNothingPlayingThereIsNoFetchAndNoDeadline() {
    var run = Run()
    run.send(.playbackReported(nil), at: 1)
    run.send(.tick, at: 2)
    #expect(run.fetches.isEmpty)
    #expect(run.state.deadline == nil)
}

@MainActor
@Test func withNothingPlayingAndLyricsOnTheStoreArmsNoTimer() {
    let scheduler = FakeScheduler()
    let store = Store(state: AppState(showsLyrics: true), clock: FakeClock(start), scheduler: scheduler)
    store.dispatch(.housingsChanged([notch]))
    store.dispatch(.lyricsChanged(true))
    store.dispatch(.playbackReported(nil))
    store.dispatch(.lyricsLoaded(grace, pass: 0))
    #expect(scheduler.armed == 0)
}

@MainActor
@Test func theStoreArmsOneTimerForTheNextLine() {
    let scheduler = FakeScheduler()
    let clock = FakeClock(start)
    let store = Store(state: AppState(showsLyrics: true), clock: clock, scheduler: scheduler)
    store.dispatch(.housingsChanged([notch]))
    store.dispatch(.playbackReported(song))
    store.dispatch(.lyricsLoaded(grace, pass: 1))
    #expect(scheduler.deadline == start + 5)
    clock.now = start + 5
    scheduler.run()
    #expect(store.state.lyrics.line?.text == "Amazing grace, how sweet the sound")
    #expect(scheduler.deadline == start + 10)
}

// MARK: The runner

@MainActor
@Test func theRunnerAnswersAFetchWithTheParsedLyricsAndTheSamePass() async {
    let provider = FakeLyrics(["Amazing Grace": lrc])
    let runner = makeRunner(lyrics: provider)
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    let query = LyricsQuery(song)!
    runner.perform(.fetchLyrics(query, pass: 4))
    runner.perform(.fetchLyrics(LyricsQuery(next("Unknown"))!, pass: 5))
    await runner.finish()
    #expect(Set(provider.asked) == [query, LyricsQuery(next("Unknown"))!])
    // The two answers may come back in either order.
    #expect(dispatched.count == 2)
    #expect(dispatched.contains(.lyricsLoaded(grace, pass: 4)))
    #expect(dispatched.contains(.lyricsLoaded(nil, pass: 5)))
}

@MainActor
@Test func theRunnerAnswersPlainLyricsAsNone() async {
    let runner = makeRunner(lyrics: FakeLyrics(["Amazing Grace": "Amazing grace, how sweet the sound"]))
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.perform(.fetchLyrics(LyricsQuery(song)!, pass: 1))
    await runner.finish()
    #expect(dispatched == [.lyricsLoaded(nil, pass: 1)])
}

@MainActor
@Test func withLyricsOffTheRunnerIsAskedNothing() {
    let provider = FakeLyrics(["Amazing Grace": lrc])
    let runner = makeRunner(lyrics: provider)
    var state = AppState()
    _ = reduce(&state, .housingsChanged([notch]), now: start)
    for (offset, action) in [AppAction.playbackReported(song), .playbackReported(next()), .tick].enumerated() {
        reduce(&state, action, now: start + Double(offset)).forEach(runner.perform)
    }
    #expect(provider.asked.isEmpty)
}
