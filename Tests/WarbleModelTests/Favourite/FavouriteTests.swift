import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let notch = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)

private func song(_ title: String = "Song", app: String = Favourite.music, playing: Bool = true) -> PlaybackState {
    PlaybackState(bundleIdentifier: app, title: title, artist: "Artist", album: "Album", elapsedTimestamp: start, rate: playing ? 1 : 0)
}

private func ask(_ number: Int, _ title: String = "Song") -> Favourite.Ask {
    Favourite.Ask(track: Favourite.Track(title: title, artist: "Artist", album: "Album"), number: number)
}

/// A notch with `playing` on it, the heart on unless `heart` is false, and the effects of everything after it.
private struct Run {
    var state = AppState()
    var effects: [AppEffect] = []
    var now = start

    init(playing: PlaybackState? = song(), heart: Bool = true) {
        send(.housingsChanged([notch]))
        if heart {
            send(.favouriteHeartChanged(true))
        }
        if let playing {
            send(.playbackReported(playing))
        }
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    mutating func wait(_ seconds: TimeInterval) {
        let end = now + seconds
        while let due = state.deadline, due <= end {
            now = due
            effects += reduce(&state, .tick, now: due)
        }
        now = end
    }

    mutating func open() {
        send(.pointer(display: "built-in", inside: true))
        wait(HoverIntent.expandDelay)
    }

    mutating func close() {
        send(.dismiss(except: nil))
    }

    var reads: [Favourite.Ask] {
        effects.compactMap { if case .readFavourite(let ask) = $0 { ask } else { nil } }
    }
}

@Test func theHeartStartsOffAndAsksMusicNothing() {
    var run = Run(heart: false)
    run.open()
    #expect(run.state.notchState("built-in") == .expanded)
    #expect(run.reads.isEmpty)
    #expect(run.state.favourite == nil)
}

@Test func openingTheCardOnAMusicSongReadsItOnce() {
    var run = Run()
    #expect(run.reads.isEmpty)
    run.open()
    #expect(run.reads == [ask(1)])
    // A new report of the same song, such as a pause, reads nothing more.
    run.send(.playbackReported(song(playing: false)), after: 1)
    run.send(.command(.togglePlayPause))
    #expect(run.reads == [ask(1)])
}

@Test func theHeartReadsNothingWhileTheCardIsClosedAndSetsNoTimer() {
    var run = Run()
    run.send(.playbackReported(song("Next")), after: 30)
    #expect(run.reads.isEmpty)
    #expect(run.state.deadline == nil)
}

@Test func theHeartShowsOnceMusicAnswers() {
    var run = Run()
    run.open()
    #expect(run.state.favourite == nil)
    run.send(.favouriteAnswered(true, ask(1)))
    #expect(run.state.favourite == true)
}

@Test func eachOpeningReadsAgainAndShowsTheLastAnswerMeanwhile() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(false, ask(1)))
    run.close()
    run.send(.pointer(display: "built-in", inside: false))
    run.open()
    #expect(run.reads == [ask(1), ask(2)])
    #expect(run.state.favourite == false)
    // Favourited in Music while the card was closed.
    run.send(.favouriteAnswered(true, ask(2)))
    #expect(run.state.favourite == true)
}

@Test func aNewSongWhileTheCardIsOpenIsReadAndHasNoHeartUntilMusicAnswers() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(true, ask(1)))
    run.send(.playbackReported(song("Next")))
    #expect(run.reads == [ask(1), ask(2, "Next")])
    #expect(run.state.favourite == nil)
    run.send(.favouriteAnswered(false, ask(2, "Next")))
    #expect(run.state.favourite == false)
}

@Test func onlyMusicHasAHeart() {
    var run = Run(playing: song(app: "com.spotify.client"))
    run.open()
    #expect(run.reads.isEmpty)
    run.send(.favouriteAnswered(true, Favourite.Ask(track: Favourite.Track(title: "Song", artist: "Artist", album: "Album"), number: 0)))
    #expect(run.state.favourite == nil)
    run.send(.toggleFavourite)
    #expect(run.effects.allSatisfy { if case .setFavourite = $0 { false } else { true } })
}

@Test func aSongWhoseFavouriteCantBeReadHasNoHeart() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(nil, ask(1)))
    #expect(run.state.favourite == nil)
    run.effects = []
    run.send(.toggleFavourite)
    #expect(run.effects.isEmpty)
}

@Test func aClickShowsTheChangeAtOnceAndSetsItInMusic() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(false, ask(1)))
    run.effects = []
    run.send(.toggleFavourite)
    #expect(run.state.favourite == true)
    #expect(run.effects == [.setFavourite(true, ask(2))])
    run.send(.favouriteAnswered(true, ask(2)))
    run.send(.toggleFavourite)
    #expect(run.state.favourite == false)
    #expect(run.effects.last == .setFavourite(false, ask(3)))
}

@Test func aSetThatFailsHidesTheHeart() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(false, ask(1)))
    run.send(.toggleFavourite)
    run.send(.favouriteAnswered(nil, ask(2)))
    #expect(run.state.favourite == nil)
}

@Test func aReadThatAClickOvertookIsDropped() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(false, ask(1)))
    run.close()
    run.send(.pointer(display: "built-in", inside: false))
    run.open()
    // The click lands before the second read answers, which then reports what was there before the click.
    run.send(.toggleFavourite)
    run.send(.favouriteAnswered(false, ask(2)))
    #expect(run.state.favourite == true)
    run.send(.favouriteAnswered(true, ask(3)))
    #expect(run.state.favourite == true)
}

@Test func anAnswerForASongThatHasGoneIsDropped() {
    var run = Run()
    run.open()
    run.send(.playbackReported(song("Next")))
    run.send(.favouriteAnswered(true, ask(1)))
    #expect(run.state.favourite == nil)
}

@Test func turningTheHeartOffHidesItAndDropsAnswersOnTheirWay() {
    var run = Run()
    run.open()
    run.send(.favouriteAnswered(true, ask(1)))
    run.send(.favouriteHeartChanged(false))
    #expect(run.state.favourite == nil)
    run.send(.favouriteAnswered(true, ask(1)))
    #expect(run.state.favourite == nil)
    // Turned on again with the card open, it reads the song afresh.
    run.effects = []
    run.send(.favouriteHeartChanged(true))
    #expect(run.reads.count == 1)
}

@Test func withNothingPlayingTheHeartAsksNothing() {
    var run = Run(playing: nil)
    run.open()
    #expect(run.state.notchState("built-in") == .note)
    #expect(run.reads.isEmpty)
    #expect(run.state.favourite == nil)
}

@MainActor
@Test func theRunnerAsksMusicAndAnswersWithAnAction() async {
    let favourites = FakeFavourites(["Song": false])
    let runner = makeRunner(favourites: favourites)
    var answers: [AppAction] = []
    runner.dispatch = { answers.append($0) }
    runner.perform(.readFavourite(ask(1)))
    for _ in 0..<100 where answers.isEmpty {
        await Task.yield()
    }
    #expect(answers == [.favouriteAnswered(false, ask(1))])
    runner.perform(.setFavourite(true, ask(2)))
    for _ in 0..<100 where answers.count < 2 {
        await Task.yield()
    }
    #expect(answers.last == .favouriteAnswered(true, ask(2)))
    #expect(await favourites.favourites["Song"] == true)
}

@Test func theScriptsAskMusicByItsBundleWithATimeoutAndFavorited() {
    let read = Favourite.readScript(title: "Song")
    #expect(read.contains("tell application id \"com.apple.Music\""))
    #expect(read.contains("with timeout of 5 seconds"))
    #expect(read.contains("return favorited of current track"))
    #expect(!read.contains("loved"))
    #expect(Favourite.setScript(true, title: "Song").contains("set favorited of current track to true"))
    #expect(Favourite.setScript(false, title: "Song").contains("set favorited of current track to false"))
}

@Test func theScriptsCheckTheTitleWithItsQuotesEscaped() {
    let script = Favourite.readScript(title: #"Say "Hi" \ Bye"#)
    #expect(script.contains(#"if name of current track is not "Say \"Hi\" \\ Bye" then"#))
}
