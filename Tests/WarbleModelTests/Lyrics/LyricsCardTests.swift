import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(
    bundleIdentifier: "com.apple.Music", title: "Amazing Grace", artist: "Traditional", album: "Hymns", duration: 200,
    elapsed: 0, elapsedTimestamp: start, rate: 1
)
/// Public domain: John Newton, 1779.
private let grace = Lyrics(lrc: """
[00:05.00] Amazing grace, how sweet the sound
[00:10.00] That saved a wretch like me
[00:15.00]
[00:20.00] I once was lost, but now am found
""")!

/// Both notches with lyrics on and `song` playing with its lyrics loaded, unless told otherwise, and the effects of
/// everything after.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(lyricsOn: Bool = true, lyrics: Lyrics? = grace, playing: PlaybackState? = song) {
        state = AppState(showsLyrics: lyricsOn)
        send(.housingsChanged([builtIn, external]))
        if let playing {
            send(.playbackReported(playing))
            send(.lyricsLoaded(lyrics, pass: state.lyrics.fetches))
        }
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    /// Lets every deadline due in `seconds` pass, as the store's timer would.
    mutating func wait(_ seconds: TimeInterval) {
        let end = now + seconds
        while let due = state.deadline, due <= end {
            now = due
            effects += reduce(&state, .tick, now: due)
        }
        now = end
    }

    /// Opens the built-in notch with a click, then asks for the lyrics, as the player's lyrics button does.
    mutating func openLyrics(after seconds: TimeInterval = 0) {
        send(.hover(display: "built-in", .click), after: seconds)
        send(.showLyrics(display: "built-in", true))
    }

    var builtInState: NotchState? { state.notchState("built-in") }
    var builtInCard: NotchCard? { state.card("built-in") }
    var current: String? { state.lyrics.excerpt?.rows.first(where: \.isCurrent)?.text }
}

@Test func withLyricsLoadedThePlayersCardOffersTheLyricsAndItsButtonSwapsToThem() {
    var run = Run()
    #expect(run.state.hasLyricsCard)
    run.send(.hover(display: "built-in", .click))
    #expect(run.builtInCard == .player)
    run.send(.showLyrics(display: "built-in", true))
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .lyrics)
}

@Test func theLyricsCardDoesntFollowTheVolume() {
    var run = Run()
    run.send(.hover(display: "built-in", .click))
    #expect(run.effects.contains(.followVolume(true)))
    run.send(.showLyrics(display: "built-in", true))
    #expect(run.effects.last == .followVolume(false))
}

@Test func theLyricsCardsButtonSwapsBackToThePlayer() {
    var run = Run()
    run.openLyrics()
    run.send(.showLyrics(display: "built-in", false))
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .player)
}

@Test func closingTheNotchDropsTheLyricsCardSoTheNextHoverOpensThePlayers() {
    var run = Run()
    run.openLyrics()
    run.send(.dismiss(except: nil), after: 1)
    #expect(run.builtInState != .expanded)
    #expect(run.state.surfaces["built-in"]?.showsLyrics == false)
    run.send(.pointer(display: "built-in", inside: true), after: 1)
    run.wait(HoverIntent.expandDelay)
    #expect(run.builtInCard == .player)
}

@Test func thePointerLeavingClosesTheLyricsCardAsAnyCard() {
    var run = Run()
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    run.send(.showLyrics(display: "built-in", true))
    run.send(.pointer(display: "built-in", inside: false), after: 1)
    run.wait(HoverIntent.collapseDelay)
    #expect(run.builtInState != .expanded)
    #expect(run.state.surfaces["built-in"]?.showsLyrics == false)
}

@Test func theLyricsCardShowsOnlyOnTheNotchThatAskedForIt() {
    var run = Run()
    run.openLyrics()
    run.send(.hover(display: "external", .click))
    #expect(run.state.card("external") == .player)
    #expect(run.builtInState != .expanded)
}

@Test func aRestingNotchCantBeAskedForTheLyrics() {
    var run = Run()
    run.send(.showLyrics(display: "built-in", true))
    #expect(run.state.surfaces["built-in"]?.showsLyrics == false)
    run.send(.hover(display: "built-in", .click))
    #expect(run.builtInCard == .player)
}

@Test func theLyricsCardMovesOnWithTheSong() {
    var run = Run()
    run.openLyrics()
    #expect(run.current == nil)
    #expect(run.state.lyrics.excerpt?.rows.first?.text == "Amazing grace, how sweet the sound")
    run.wait(6)
    #expect(run.current == "Amazing grace, how sweet the sound")
    run.wait(5)
    #expect(run.current == "That saved a wretch like me")
}

@Test func thePausedLyricsCardKeepsItsLinesAndAsksForNoDeadline() {
    var run = Run()
    run.send(.playbackReported(song.playing(false, at: start + 12)), after: 12)
    run.openLyrics()
    #expect(run.builtInCard == .lyrics)
    #expect(run.current == "That saved a wretch like me")
    #expect(run.state.lyrics.deadline == nil)
}

@Test func turningLyricsOffSwapsTheOpenLyricsCardForThePlayers() {
    var run = Run()
    run.openLyrics()
    run.send(.lyricsChanged(false))
    #expect(!run.state.hasLyricsCard)
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .player)
}

@Test func aNewTrackWithoutLyricsUnderTheOpenLyricsCardShowsThePlayers() {
    var run = Run()
    run.openLyrics()
    var next = song
    next.title = "Instrumental"
    run.send(.playbackReported(next), after: 1)
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .player)
    run.send(.lyricsLoaded(nil, pass: run.state.lyrics.fetches))
    #expect(run.builtInCard == .player)
}

// MARK: When there's no lyrics card

@Test func withLyricsOffThereIsNoLyricsCard() {
    var run = Run(lyricsOn: false)
    #expect(!run.state.hasLyricsCard)
    run.openLyrics()
    #expect(run.builtInCard == .player)
}

@Test func withNoLyricsForTheSongThereIsNoLyricsCard() {
    var run = Run(lyrics: nil)
    #expect(!run.state.hasLyricsCard)
    run.openLyrics()
    #expect(run.builtInCard == .player)
}

@Test func withLyricsThatHaveNoWordsThereIsNoLyricsCard() {
    var run = Run(lyrics: Lyrics(lrc: "[00:01.00]\n[00:02.00]")!)
    #expect(run.state.lyrics.excerpt == nil)
    run.openLyrics()
    #expect(run.builtInCard == .player)
}

@Test func withNothingPlayingThereIsNoLyricsCardAndNothingIsDue() {
    var run = Run(playing: nil)
    #expect(!run.state.hasLyricsCard)
    run.openLyrics()
    #expect(run.builtInCard == .idle)
    run.send(.dismiss(except: nil))
    #expect(run.state.deadline == nil)
}

@Test func whileIdleThePausedSongsLyricsOfferNoCard() {
    var run = Run()
    run.send(.playbackReported(song.playing(false, at: start + 12)), after: 12)
    run.wait(IdleAfterPause.defaultDelay + 1)
    #expect(!run.state.showsPlayback)
    #expect(!run.state.hasLyricsCard)
    run.openLyrics()
    #expect(run.builtInCard == .idle)
    run.send(.dismiss(except: nil))
    #expect(run.state.deadline == nil)
}
