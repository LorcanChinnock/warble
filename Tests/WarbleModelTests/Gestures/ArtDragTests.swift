import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let builtIn = NotchHousing(display: "built-in", frame: CGRect(x: 856, y: 1205.5, width: 208, height: 37.5), isVirtual: false)
private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00])
private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])
private let link = URL(string: "https://open.spotify.com/track/0aym2LBJBk9DAYuHHutrIl")!

private func song(link: URL? = link, artwork: Data? = jpeg) -> PlaybackState {
    PlaybackState(
        bundleIdentifier: "com.spotify.client", title: "Hey Jude", artist: "The Beatles", duration: 431,
        elapsedTimestamp: start, rate: 1, artwork: artwork, link: link
    )
}

/// A notch with dragging the art on and `song()` playing, unless told otherwise, and the effects of everything after.
private struct Run {
    var state: AppState
    var effects: [AppEffect] = []
    var now = start

    init(dragArtOut: Bool = true, playing: PlaybackState? = song()) {
        state = AppState(dragArtOut: dragArtOut)
        send(.housingsChanged([builtIn]))
        if let playing {
            send(.sourceReported(bundleIdentifier: "app", playing))
        }
        effects = []
    }

    mutating func send(_ action: AppAction, after seconds: TimeInterval = 0.01) {
        now += seconds
        effects += reduce(&state, action, now: now)
    }

    /// Opens the notch with a click, with the pointer on it.
    mutating func open() {
        send(.pointer(display: "built-in", inside: true))
        send(.hover(display: "built-in", .click))
    }

    /// Lets the store's timer fire for every deadline due in the next `seconds`.
    mutating func wait(_ seconds: TimeInterval) {
        let until = now + seconds
        while let deadline = state.deadline, deadline <= until {
            now = deadline
            effects += reduce(&state, .tick, now: now)
        }
        now = until
    }

    var notch: NotchState? { state.notchState("built-in") }

    var takesEscape: Bool? {
        effects.compactMap { if case .takeEscape(let takes) = $0 { takes } else { nil } }.last
    }
}

@Test func aDragCarriesTheLinkAndTheArt() throws {
    let drag = try #require(ArtDrag(song()))
    #expect(drag.link == link)
    #expect(drag.image == jpeg)
    #expect(drag.fileName == "Hey Jude.jpg")
}

@Test func withoutALinkADragCarriesTheArtAlone() throws {
    let drag = try #require(ArtDrag(song(link: nil)))
    #expect(drag.link == nil)
    #expect(drag.image == jpeg)
}

@Test func withoutArtADragCarriesTheLinkAlone() throws {
    let drag = try #require(ArtDrag(song(artwork: nil)))
    #expect(drag.link == link)
    #expect(drag.image == nil)
    #expect(drag.fileName == nil)
}

@Test func withNeitherThereIsNothingToDrag() {
    #expect(ArtDrag(song(link: nil, artwork: nil)) == nil)
}

@Test func theArtDropsAsAFileNamedForTheTrack() {
    #expect(ArtDrag.fileName(title: "Hey Jude", image: png) == "Hey Jude.png")
    #expect(ArtDrag.fileName(title: "Hey Jude", image: Data([0x4D, 0x4D, 0x00, 0x2A])) == "Hey Jude.tiff")
    #expect(ArtDrag.fileName(title: "AC/DC: Live", image: jpeg) == "AC-DC- Live.jpg")
    #expect(ArtDrag.fileName(title: "..hidden", image: jpeg) == "hidden.jpg")
    #expect(ArtDrag.fileName(title: " ", image: jpeg) == "Artwork.jpg")
}

@Test func theArtCanBeDraggedOnlyWithTheSettingOnAndSomethingPlaying() {
    #expect(Run().state.artDrag == ArtDrag(song()))
    #expect(Run(dragArtOut: false).state.artDrag == nil)
    #expect(Run(playing: nil).state.artDrag == nil)
    #expect(Run(playing: song(link: nil, artwork: nil)).state.artDrag == nil)
}

@Test func turningTheSettingOnLetsTheArtBeDragged() {
    var run = Run(dragArtOut: false)
    run.send(.dragArtOutChanged(true))
    #expect(run.state.artDrag != nil)
    run.send(.dragArtOutChanged(false))
    #expect(run.state.artDrag == nil)
}

@Test func theNotchStaysOpenWhileTheArtIsDragged() {
    var run = Run()
    run.open()
    run.send(.hover(display: "built-in", .dragging(true)))
    run.send(.pointer(display: "built-in", inside: false))
    run.wait(5)
    #expect(run.notch == .expanded)
}

@Test func aClickOutsideOrEscapeDoesNotCloseTheNotchMidDrag() {
    var run = Run()
    run.open()
    run.send(.hover(display: "built-in", .dragging(true)))
    run.send(.dismiss(except: nil))
    #expect(run.notch == .expanded)
}

@Test func theNotchClosesAsUsualOnceTheDragEndsElsewhere() {
    var run = Run()
    run.open()
    run.send(.hover(display: "built-in", .dragging(true)))
    run.send(.pointer(display: "built-in", inside: false))
    run.wait(5)
    run.send(.hover(display: "built-in", .dragging(false)))
    run.wait(HoverIntent.collapseDelay / 2)
    #expect(run.notch == .expanded)
    run.wait(HoverIntent.collapseDelay)
    #expect(run.notch == .resting)
    #expect(run.state.deadline == nil)
}

@Test func aDragThatEndsOnTheNotchLeavesItOpen() {
    var run = Run()
    run.send(.pointer(display: "built-in", inside: true))
    run.wait(HoverIntent.expandDelay)
    run.send(.hover(display: "built-in", .dragging(true)))
    run.send(.hover(display: "built-in", .dragging(false)))
    run.wait(5)
    #expect(run.notch == .expanded)
}

@Test func escapeIsLetGoWhileTheArtIsDragged() {
    var run = Run()
    run.open()
    #expect(run.takesEscape == true)
    run.send(.hover(display: "built-in", .dragging(true)))
    #expect(run.takesEscape == false)
    run.send(.hover(display: "built-in", .dragging(false)))
    #expect(run.takesEscape == true)
}

@Test func playbackStoppingMidDragLeavesNothingToDragAndNoTimerOnceItEnds() {
    var run = Run()
    run.open()
    run.send(.hover(display: "built-in", .dragging(true)))
    run.send(.pointer(display: "built-in", inside: false))
    run.send(.sourceReported(bundleIdentifier: "app", nil))
    run.wait(AppState.hideDelay)
    #expect(run.state.artDrag == nil)
    run.send(.hover(display: "built-in", .dragging(false)))
    run.wait(5)
    #expect(run.notch == .idle)
    #expect(run.state.deadline == nil)
}
