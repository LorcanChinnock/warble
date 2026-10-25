import Foundation
import Testing
@testable import WarbleModel

private let start = activityStart
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(
    bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", album: "Album", duration: 200, elapsed: 0, elapsedTimestamp: start, rate: 1
)
private let notch = CGRect(x: 856, y: 1205.5, width: 208, height: 37.5)

/// Both notches with activities on, and the effects of everything after.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(playing: Bool = false, idleHover: IdleHover = .lastPlayed, toasts: Bool = false, lyrics: Bool = false, checks: [Doctor.Check] = []) {
        state = AppState(idleHover: idleHover, showsTrackToast: toasts, showsLyrics: lyrics, showsActivities: true, checks: checks)
        send(.housingsChanged([builtIn, external]))
        if playing {
            send(.playbackReported(song))
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

    mutating func startActivity(_ id: String = "recording", priority: ActivityPriority = .normal, client: Int = 1) {
        send(.activityStarted(activity(id, client: client, priority: priority, lasts: 3600)))
    }

    mutating func open(_ display: String = "built-in") {
        send(.hover(display: display, .click))
    }

    var builtInState: NotchState? { state.notchState("built-in") }
    var builtInCard: NotchCard? { state.card("built-in") }
}

// MARK: The wings

@Test func anActivityTakesTheRestingWingsFromMusic() {
    var run = Run(playing: true)
    #expect(run.builtInState == .resting)
    run.startActivity()
    #expect(run.builtInState == .activity)
    #expect(run.state.notchState("external") == .activity)
    run.send(.activityEnded(activity().key))
    #expect(run.builtInState == .resting)
}

@Test func anActivityDrawsWhereNothingWouldBeDrawnAtAll() {
    var run = Run(idleHover: .nothing)
    #expect(run.builtInState == .hidden)
    run.startActivity()
    #expect(run.builtInState == .activity)
    run.send(.activityEnded(activity().key))
    #expect(run.builtInState == .hidden)
}

@Test func anActivityDrawsInPlaceOfAnIdleHousing() {
    var run = Run()
    #expect(run.builtInState == .idle)
    run.startActivity()
    #expect(run.builtInState == .activity)
}

@Test func anActivityTakesTheWingsFromTheDoctorsBang() {
    var run = Run(playing: true, checks: [Doctor.Check(.adapter, .fail, .adapterMissing, fix: .reinstall)])
    #expect(run.state.needsAttention)
    run.startActivity()
    #expect(run.builtInState == .activity)
    run.send(.activityEnded(activity().key))
    #expect(run.builtInState == .resting)
}

@Test func theTrackToastIsSkippedWhileAnActivityShowsAndNotHeld() {
    var run = Run(playing: true, toasts: true)
    run.startActivity()
    run.send(.playbackReported(PlaybackState(bundleIdentifier: "com.apple.Music", title: "Next", artist: "Artist", elapsedTimestamp: start, rate: 1)))
    #expect(run.state.toasts.current != nil)
    #expect(run.builtInState == .activity)
    // The toast's own deadline runs out under the activity, so it's gone when the activity ends.
    run.wait(TrackToast.duration + 1)
    #expect(run.state.toasts.current == nil)
    run.send(.activityEnded(activity().key))
    #expect(run.builtInState == .resting)
}

@Test func theLyricLineGivesWayToAnActivity() {
    var run = Run(playing: true, lyrics: true)
    let lyrics = Lyrics(lrc: "[00:00.00] A line\n[00:30.00] Another")!
    run.send(.lyricsLoaded(lyrics, pass: run.state.lyrics.fetches))
    #expect(run.builtInState == .lyrics)
    run.startActivity()
    #expect(run.builtInState == .activity)
    run.send(.activityEnded(activity().key))
    #expect(run.builtInState == .lyrics)
}

@Test func aFullScreenAppHidesTheActivityEvenWhereToastsAreLetThrough() {
    var run = Run()
    run.send(.fullScreenChanged(["built-in"]))
    run.startActivity()
    #expect(run.builtInState == .hidden)
    #expect(run.state.notchState("external") == .activity)
    var toasts = Run(playing: true, toasts: true)
    toasts.send(.toastsInFullScreenChanged(true))
    toasts.send(.fullScreenChanged(["built-in"]))
    toasts.startActivity()
    #expect(toasts.builtInState == .hidden)
}

@Test func aNotchOverAFullScreenAppTakesNoPointerEvenWithAnActivity() {
    var run = Run()
    run.send(.fullScreenChanged(["built-in"]))
    run.startActivity()
    run.send(.pointer(display: "built-in", inside: true))
    #expect(run.state.surfaces["built-in"]?.pointerInside == false)
}

// MARK: Opening

@Test func hoveringOrClickingAnActivityOpensThePlayer() {
    var run = Run(playing: true)
    run.startActivity()
    run.open()
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .player)
}

@Test func withNothingPlayingTheOpenCardIsTheActivityCard() {
    var run = Run()
    run.startActivity()
    run.open()
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .activity)
}

@Test func aLiveActivityOpensWhateverIdleHoverIsSetTo() {
    var run = Run(idleHover: .nothing)
    run.startActivity()
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .activity)
    #expect(run.state.hovering)
}

@Test func theActivityCardGoesBackToNothingWhenTheLastActivityEnds() {
    var run = Run(idleHover: .nothing)
    run.startActivity()
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    run.send(.activityEnded(activity().key))
    #expect(run.builtInState == .hidden)
    #expect(run.state.surfaces["built-in"]?.pointerInside == false)
    #expect(!run.state.hovering)
}

@Test func anActivityStartingUnderThePointerDoesntMoveItsState() {
    var run = Run(playing: true)
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.builtInState == .expanded)
    run.startActivity()
    #expect(run.builtInState == .expanded)
    #expect(run.builtInCard == .player)
    #expect(run.state.surfaces["built-in"]?.pointerInside == true)
}

@Test func anActivityDoesntTakeTheKeyboard() {
    var run = Run(playing: true)
    run.startActivity()
    #expect(!run.effects.contains(.toggleKeyboard))
    #expect(!run.effects.contains(.takeEscape(true)))
    #expect(!run.effects.contains(.watchClicksOutside(true)))
}

@Test func theDoctorsCardIsAsItWasWhenOpenedOnPurpose() {
    var run = Run(playing: true, checks: [Doctor.Check(.adapter, .fail, .adapterMissing, fix: .reinstall)])
    run.startActivity()
    run.open()
    run.send(.showDoctor(display: "built-in", true))
    #expect(run.builtInCard == .doctor)
}

@Test func theLyricsCardKeepsItsContentWithAnActivityLive() {
    var run = Run(playing: true, lyrics: true)
    run.send(.lyricsLoaded(Lyrics(lrc: "[00:00.00] A line\n[00:30.00] Another")!, pass: run.state.lyrics.fetches))
    run.startActivity()
    run.open()
    run.send(.showLyrics(display: "built-in", true))
    #expect(run.builtInCard == .lyrics)
}

@Test func theActivityCardIsAskedForOnlyWhenNothingPlays() {
    var run = Run()
    run.startActivity()
    run.open()
    // The volume slider is the player's.
    #expect(!run.effects.contains(.followVolume(true)))
    run.send(.playbackReported(song))
    #expect(run.builtInCard == .player)
    #expect(run.effects.contains(.followVolume(true)))
}

@Test func openingTheActivityCardWatchesClicksSoAClickOutsideClosesIt() {
    var run = Run()
    run.startActivity()
    run.open()
    #expect(run.effects.contains(.watchClicksOutside(true)))
    run.send(.dismiss(except: nil))
    #expect(run.builtInState == .activity)
}

// MARK: The audio tap

@Test func theBarsAreNotDrawnWhileAnActivityCoversThem() {
    var run = Run(playing: true)
    run.send(.waveformChanged(true))
    #expect(run.state.drawsBars)
    #expect(run.state.capturesAudio)
    run.startActivity()
    #expect(!run.state.drawsBars)
    #expect(run.effects.contains(.captureAudio(false)))
    run.send(.activityEnded(activity().key))
    #expect(run.state.drawsBars)
    #expect(run.effects.last == .captureAudio(true))
}

// MARK: The selectors

@Test func anActivityRestingStateHasNoMusicOrToastUnderIt() {
    #expect(NotchState(.resting, isPlaying: true, needsAttention: false, idleHover: .lastPlayed, showsToast: true, showsLyrics: true, showsActivity: true) == .activity)
    #expect(NotchState(.resting, isPlaying: false, needsAttention: true, idleHover: .lastPlayed, showsActivity: true) == .activity)
    #expect(NotchState(.resting, isPlaying: false, needsAttention: false, idleHover: .nothing, isAlwaysShown: true, showsActivity: true) == .activity)
}

@Test func anOpenedNotchWithAnActivityIsExpanded() {
    for idleHover in [IdleHover.lastPlayed, .nothing] {
        #expect(NotchState(.expanded, isPlaying: false, needsAttention: false, idleHover: idleHover, showsActivity: true) == .expanded)
        #expect(NotchState(.pinned, isPlaying: true, needsAttention: false, idleHover: idleHover, showsActivity: true) == .expanded)
    }
}

@Test func theCardForAnActivityComesAfterThePlayerAndBeforeTheDoctorsFailedCheck() {
    #expect(NotchCard(isPlaying: true, needsAttention: false, showsDoctor: false, showsActivity: true) == .player)
    #expect(NotchCard(isPlaying: true, needsAttention: false, showsDoctor: false, showsLyrics: true, showsActivity: true) == .lyrics)
    #expect(NotchCard(isPlaying: true, needsAttention: false, showsDoctor: true, showsActivity: true) == .doctor)
    #expect(NotchCard(isPlaying: false, needsAttention: true, showsDoctor: false, showsActivity: true) == .activity)
    #expect(NotchCard(isPlaying: false, needsAttention: true, showsDoctor: true, showsActivity: true) == .doctor)
    #expect(NotchCard(isPlaying: false, needsAttention: false, showsDoctor: false, showsActivity: true) == .activity)
    #expect(NotchCard(isPlaying: false, needsAttention: false, showsDoctor: false) == .idle)
}

// MARK: The layout

@Test func theWingsOfAnActivityAreTheRestingFrameAndOnlyTheHousingTakesTheHover() {
    #expect(NotchLayout.frame(.activity, notch: notch) == NotchLayout.frame(.resting, notch: notch))
    #expect(NotchLayout.hoverArea(.activity, notch: notch) == notch)
}

@Test func thePlayersCardGrowsByARowForEachActivityBelowItsControls() throws {
    let bare = try #require(NotchLayout.frame(.expanded, notch: notch))
    let one = try #require(NotchLayout.frame(.expanded, notch: notch, card: .player, activityRows: 1))
    let three = try #require(NotchLayout.frame(.expanded, notch: notch, card: .player, activityRows: 3))
    #expect(one.height - bare.height == NotchLayout.activityRowDrop)
    #expect(three.height - bare.height == 3 * NotchLayout.activityRowDrop)
    // It grows downward, so the controls and the housing stay where they were.
    #expect(one.maxY == bare.maxY)
    #expect(one.minX == bare.minX && one.width == bare.width)
}

@Test func theLyricsCardIsAlwaysThePlayersSizeSoItsButtonStaysUnderThePointer() throws {
    for rows in 0...3 {
        let player = try #require(NotchLayout.frame(.expanded, notch: notch, card: .player, activityRows: rows))
        let lyrics = try #require(NotchLayout.frame(.expanded, notch: notch, card: .lyrics, activityRows: rows))
        #expect(player == lyrics)
    }
}

@Test func theActivityCardIsTheIdleCardsHeightForOneRowAndARowMoreForEachExtra() throws {
    let idle = try #require(NotchLayout.frame(.expanded, notch: notch, card: .idle))
    let one = try #require(NotchLayout.frame(.expanded, notch: notch, card: .activity, activityRows: 1))
    let three = try #require(NotchLayout.frame(.expanded, notch: notch, card: .activity, activityRows: 3))
    #expect(one == idle)
    #expect(three.height - idle.height == 2 * NotchLayout.activityRowDrop)
}

@Test func theOpenAreaFollowsTheCardAndItsRows() {
    #expect(NotchLayout.hoverArea(.expanded, notch: notch, card: .player, activityRows: 2) == NotchLayout.frame(.expanded, notch: notch, card: .player, activityRows: 2))
}

@Test func theDoctorsCardDoesntGrowWithActivities() {
    #expect(NotchLayout.frame(.expanded, notch: notch, card: .doctor, activityRows: 2) == NotchLayout.frame(.expanded, notch: notch, card: .doctor))
}

// MARK: Nothing live

@Test func withNoActivityNothingIsDrawnOrScheduledForThem() {
    var run = Run()
    #expect(run.state.deadline == nil)
    #expect(run.builtInState == .idle)
    run.startActivity()
    run.send(.activityEnded(activity().key))
    #expect(run.state.deadline == nil)
    #expect(run.builtInState == .idle)
}

@Test func anActivityThatExpiresGivesTheWingsBackToTheMusic() {
    var run = Run(playing: true)
    run.send(.activityStarted(activity(lasts: 60)))
    run.wait(61)
    #expect(run.builtInState == .resting)
    #expect(run.effects.contains(.sendActivityEvent(activity().key, .ended(.expired))))
}
