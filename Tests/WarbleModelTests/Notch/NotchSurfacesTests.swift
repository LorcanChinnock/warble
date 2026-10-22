import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)

/// A state with both notches and `song` playing, and the effects of everything after it.
private struct Run {
    var state = AppState()
    var effects: [AppEffect] = []
    var now = start

    init(playing: PlaybackState? = song, idleHover: IdleHover = .lastPlayed) {
        state = AppState(idleHover: idleHover)
        send(.housingsChanged([builtIn, external]))
        if let playing {
            send(.playbackReported(playing))
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

    /// Opens `display` by resting the pointer on it.
    mutating func hover(_ display: String) {
        send(.pointer(display: display, inside: true))
        wait(HoverIntent.expandDelay)
    }
}

@Test func restingThePointerOpensANotchAfterTheDelayAndLeavingClosesIt() {
    var run = Run()
    run.send(.pointer(display: "built-in", inside: true))
    #expect(run.state.notchState("built-in") == .resting)
    #expect(run.state.deadline == start + HoverIntent.expandDelay)
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("built-in") == .expanded)
    run.send(.pointer(display: "built-in", inside: false))
    run.wait(HoverIntent.collapseDelay)
    #expect(run.state.notchState("built-in") == .resting)
    #expect(run.state.deadline == nil)
}

@Test func twoNotchesShareTheEarliestDeadline() {
    var run = Run()
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.pointer(display: "external", inside: true), after: 0.1)
    #expect(run.state.deadline == start + HoverIntent.expandDelay)
    run.wait(HoverIntent.expandDelay - 0.1)
    #expect(run.state.notchState("built-in") == .expanded)
    #expect(run.state.notchState("external") == .resting)
    #expect(run.state.deadline == start + 0.1 + HoverIntent.expandDelay)
}

@Test func aClickOutsideClosesEveryOpenNotchAndStopsWatching() {
    var run = Run()
    run.send(.hover(display: "built-in", .click))
    #expect(run.effects.contains(.watchClicksOutside(true)))
    run.send(.dismiss(except: nil))
    #expect(run.state.notchState("built-in") == .resting)
    #expect(run.effects.suffix(2) == [.watchClicksOutside(false), .followVolume(false)])
}

@Test func aClickOnOneNotchClosesTheOther() {
    var run = Run()
    run.send(.hover(display: "external", .click))
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.notchState("external") == .resting)
    #expect(run.state.notchState("built-in") == .expanded)
}

@Test func escapeIsTakenOnlyWhileAnOpenNotchHasThePointer() {
    var run = Run()
    run.hover("built-in")
    #expect(run.effects == [.watchClicksOutside(true), .takeEscape(true), .followVolume(true)])
    run.effects = []
    run.send(.menu(display: "built-in", open: true))
    #expect(run.effects == [.takeEscape(false)])
    run.send(.menu(display: "built-in", open: false))
    #expect(run.effects == [.takeEscape(false), .takeEscape(true)])
    run.effects = []
    run.send(.pointer(display: "built-in", inside: false))
    #expect(run.effects == [.takeEscape(false)])
    run.wait(HoverIntent.collapseDelay)
    #expect(run.effects == [.takeEscape(false), .watchClicksOutside(false), .followVolume(false)])
}

@Test func onlyThePlayersCardFollowsTheVolume() {
    var run = Run(playing: nil)
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.card("built-in") == .idle)
    #expect(!run.effects.contains(.followVolume(true)))
}

@Test func theDoctorsCardShowsUntilTheNotchCloses() {
    var run = Run()
    // The resting "!" asks for the checks, then its click opens the notch on them.
    run.send(.showDoctor(display: "built-in", true))
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.card("built-in") == .doctor)
    run.send(.dismiss(except: nil))
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.card("built-in") == .player)
}

@Test func withIdleHoverOffNothingShowsAndHoveringDoesNothing() {
    var run = Run(playing: nil, idleHover: .nothing)
    #expect(run.state.notchState("built-in") == .hidden)
    run.hover("built-in")
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.notchState("built-in") == .hidden)
    #expect(run.effects.isEmpty)
    #expect(run.state.deadline == nil)
}

@Test func withNothingPlayingAndNothingOpenNothingIsDueOrWatched() {
    let run = Run(playing: nil)
    #expect(run.state.notchState("built-in") == .idle)
    #expect(run.state.deadline == nil)
    #expect(!run.state.watchesClicks)
    #expect(!run.state.takesEscape)
}

@Test func aNotchThatStopsAnsweringForgetsThePointer() {
    var run = Run(idleHover: .nothing)
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.playbackReported(nil))
    run.wait(AppState.hideDelay)
    #expect(run.state.notchState("built-in") == .hidden)
    #expect(run.state.surfaces["built-in"]?.pointerInside == false)
    #expect(run.state.deadline == nil)
}

@Test func anOpenNotchHoldsOffIdleAndDismissesTheToast() {
    var run = Run()
    run.state.showsTrackToast = true
    run.send(.playbackReported(PlaybackState(bundleIdentifier: "com.apple.Music", title: "Next", elapsedTimestamp: start, rate: 1)))
    #expect(run.state.notchState("built-in") == .toast)
    run.send(.hover(display: "built-in", .click))
    #expect(run.state.toasts.current == nil)
    #expect(run.state.hovering)
}

@Test func playbackStoppingDismissesTheToastSoTheSameTrackReturningDoesntBringItBack() {
    var run = Run()
    run.state.showsTrackToast = true
    let next = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Next", elapsedTimestamp: start, rate: 1)
    run.send(.playbackReported(next))
    #expect(run.state.toasts.current != nil)
    run.send(.playbackReported(nil), after: 0.1)
    run.wait(AppState.hideDelay)
    #expect(!run.state.showsPlayback)
    #expect(run.state.toasts.current == nil)
    #expect(run.state.deadline == nil)
    run.send(.playbackReported(next), after: 0.1)
    #expect(run.state.notchState("built-in") == .resting)
}

@Test func aToastIsntPostedWhileANotchIsOpen() {
    var run = Run()
    run.state.showsTrackToast = true
    run.send(.hover(display: "built-in", .click))
    run.send(.playbackReported(PlaybackState(bundleIdentifier: "com.apple.Music", title: "Next", elapsedTimestamp: start, rate: 1)))
    #expect(run.state.toasts.current == nil)
}

@Test func housingsThatStayKeepTheirHover() {
    var run = Run()
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.housingsChanged([builtIn]))
    #expect(run.state.surfaces["built-in"]?.pointerInside == true)
    #expect(run.state.surfaces["external"] == nil)
}

@MainActor
@Test func theRunnerTakesEscapeAndAPressClosesTheNotches() {
    let hotkeys = FakeHotkeys()
    let runner = makeRunner(hotkeys: hotkeys)
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.perform(.takeEscape(true))
    #expect(hotkeys.temporary[.notch] == .escape)
    hotkeys.press(.notch)
    #expect(dispatched == [.dismiss(except: nil)])
    runner.perform(.takeEscape(false))
    #expect(hotkeys.temporary[.notch] == nil)
}

@MainActor
@Test func theRunnerLetsGoOnlyOfAnEscapeItHolds() {
    let hotkeys = FakeHotkeys()
    hotkeys.refuses = true
    let runner = makeRunner(hotkeys: hotkeys)
    runner.perform(.takeEscape(true))
    runner.perform(.takeEscape(false))
    #expect(hotkeys.unregisters == 0)
}

private let undo = KeyCombo(keyCode: 6, modifiers: KeyCombo.command)

@MainActor
@Test func aToastsKeyTakenWhileEscapeIsHeldLeavesBothAndEscapeLetsGoOfOnlyItself() {
    let hotkeys = FakeHotkeys()
    let runner = makeRunner(hotkeys: hotkeys)
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.perform(.takeEscape(true))
    hotkeys.registerTemporary(undo, for: .toast) {}
    #expect(hotkeys.temporary == [.notch: .escape, .toast: undo])
    hotkeys.press(.notch)
    #expect(dispatched == [.dismiss(except: nil)])
    runner.perform(.takeEscape(false))
    #expect(hotkeys.temporary == [.toast: undo])
}

@MainActor
@Test func takingEscapeWhileAToastHoldsItsKeyLeavesThatKeyAndTheToastLetsGoOfOnlyItsOwn() {
    let hotkeys = FakeHotkeys()
    let runner = makeRunner(hotkeys: hotkeys)
    var undone = false
    hotkeys.registerTemporary(undo, for: .toast) { undone = true }
    runner.perform(.takeEscape(true))
    #expect(hotkeys.temporary == [.notch: .escape, .toast: undo])
    hotkeys.press(.toast)
    #expect(undone)
    hotkeys.unregisterTemporary(for: .toast)
    #expect(hotkeys.temporary == [.notch: .escape])
}

@MainActor
@Test func theRunnerHandsAppKitEffectsToThePlatform() {
    let runner = makeRunner()
    var handed: [AppEffect] = []
    runner.platform = { handed.append($0) }
    runner.perform(.watchClicksOutside(true))
    runner.perform(.haptic)
    runner.perform(.openApp(bundleIdentifier: "com.apple.Music"))
    #expect(handed == [.watchClicksOutside(true), .haptic, .openApp(bundleIdentifier: "com.apple.Music")])
}

@MainActor
@Test func theDisplaysGiveTheHousingsTheirRulesCallFor() {
    let displays = FakeDisplays()
    var changes = 0
    displays.onChange = { changes += 1 }
    displays.displays = [NotchDisplay(id: "external", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), menuBarHeight: 24, notch: nil, isMain: true)]
    #expect(changes == 1)
    #expect(displays.housings(rules: [:]).map(\.display) == ["external"])
    #expect(displays.housings(rules: ["external": .off]).isEmpty)
}

