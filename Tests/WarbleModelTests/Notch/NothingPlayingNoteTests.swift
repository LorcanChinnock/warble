import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let external = NotchHousing(display: "external", frame: CGRect(x: 2800, y: 1400, width: 160, height: 24), isVirtual: true)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", elapsedTimestamp: start, rate: 1)

private struct Run {
    var state = AppState.pausingAfterTenSeconds()
    var effects: [AppEffect] = []
    var now = start

    init(_ housings: [NotchHousing], _ visibility: VirtualNotchVisibility = .standard) {
        send(.housingsChanged(housings))
        send(.virtualVisibilityChanged(visibility))
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
}

@Test func aRealNotchWithNothingPlayingIsEmptyAndTakesTheHover() {
    var run = Run([builtIn])
    #expect(run.state.notchState("built-in") == .empty)
    run.send(.pointer(display: "built-in", inside: true))
    #expect(run.state.deadline == start + HoverIntent.expandDelay)
}

@Test func pointingAtAnEmptyNotchOpensTheNoteAfterTheSameDelayAsThePlayer() {
    var run = Run([builtIn])
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay - 0.01)
    #expect(run.state.notchState("built-in") == .empty)
    run.wait(0.01)
    #expect(run.state.notchState("built-in") == .note)
    #expect(NotchLayout.hoverArea(.note, notch: builtIn.frame) == NotchLayout.frame(.note, notch: builtIn.frame))
}

@Test func theNoteClosesWhenThePointerLeaves() {
    var run = Run([builtIn])
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    run.send(.pointer(display: "built-in", inside: false))
    run.wait(HoverIntent.collapseDelay)
    #expect(run.state.notchState("built-in") == .empty)
    #expect(run.state.deadline == nil)
}

@Test func theNoteClosesOnAClickElsewhereAndWatchesClicksOnlyWhileOpen() {
    var run = Run([builtIn])
    run.send(.pointer(display: "built-in", inside: true))
    #expect(!run.state.watchesClicks)
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.watchesClicks)
    #expect(run.effects.contains(.watchClicksOutside(true)))
    run.send(.dismiss(except: nil))
    #expect(run.state.notchState("built-in") == .empty)
    #expect(!run.state.watchesClicks)
}

@Test func theNoteHasNoSliderSoFollowsNoVolume() {
    var run = Run([builtIn])
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("built-in") == .note)
    #expect(!run.state.followsVolume)
    #expect(!run.effects.contains(.followVolume(true)))
}

@Test func aSongThatStartsWhileTheNoteIsOpenTurnsItIntoThePlayer() {
    var run = Run([builtIn])
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    run.send(.playbackReported(song))
    #expect(run.state.notchState("built-in") == .expanded)
    #expect(run.state.followsVolume)
}

@Test func aSongThatStopsUnderTheOpenPlayerLeavesTheNote() {
    var run = Run([builtIn])
    run.send(.playbackReported(song))
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    run.send(.playbackReported(nil))
    run.wait(AppState.hideDelay)
    #expect(run.state.notchState("built-in") == .note)
    #expect(!run.state.followsVolume)
}

@Test func aVirtualNotchThatIsNotKeptHasNothingToPointAt() {
    var run = Run([external])
    #expect(run.state.notchState("external") == .hidden)
    run.send(.pointer(display: "external", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("external") == .hidden)
    #expect(!run.state.hovering)
    #expect(run.state.deadline == nil)
}

@Test func aVirtualNotchSetToOffNeverShowsTheNote() {
    var run = Run([external], .off)
    run.send(.pointer(display: "external", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("external") == .hidden)
}

@Test func anAlwaysVirtualNotchOpensTheNote() {
    var run = Run([external], .always)
    run.send(.pointer(display: "external", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("external") == .note)
}

@Test func theNoteIsHiddenOverAFullScreenApp() {
    var run = Run([builtIn])
    run.send(.fullScreenChanged(["built-in"]))
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    #expect(run.state.notchState("built-in") == .hidden)
}

@Test func anEmptyNotchSetsNoTimerUntilThePointerIsOnIt() {
    var run = Run([builtIn, external], .always)
    #expect(run.state.deadline == nil)
    run.send(.pointer(display: "built-in", inside: true))
    run.send(.pointer(display: "built-in", inside: false))
    run.wait(HoverIntent.collapseDelay)
    #expect(run.state.deadline == nil)
}

@Test func theNoteIsAShortCardUnderTheHousingAsWideAsTheWings() {
    let housing = builtIn.frame
    let note = NotchLayout.frame(.note, notch: housing)
    #expect(note?.minY == housing.minY - NotchLayout.noteDrop)
    #expect(note?.width == housing.width + 2 * NotchLayout.wing(notch: housing))
    #expect(note?.maxY == housing.maxY)
    #expect(NotchState.note.isOpen && NotchState.expanded.isOpen)
    #expect(!NotchState.empty.isOpen && !NotchState.resting.isOpen)
}

@Test func scrollingOverAnEmptyNotchLeavesTheVolumeAlone() {
    var run = Run([builtIn])
    run.send(.scrolled(delta: 4, precise: true, inverted: false, volume: 0.5, isMuted: false))
    #expect(run.effects.isEmpty)
    run.send(.playbackReported(song))
    run.send(.scrolled(delta: 4, precise: true, inverted: false, volume: 0.5, isMuted: false))
    #expect(!run.effects.isEmpty)
}
