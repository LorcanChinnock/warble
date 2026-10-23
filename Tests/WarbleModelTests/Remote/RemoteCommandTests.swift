import Foundation
import Testing
@testable import WarbleModel

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let song = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", artist: "Artist", duration: 200, elapsed: 10, elapsedTimestamp: start, rate: 1)

private func link(_ text: String) -> RemoteCommand? {
    URL(string: text).flatMap(RemoteCommand.init(url:))
}

@Test(arguments: ["warble", "warble-dev"])
func eachRouteParsesToTheActionItsButtonDispatches(scheme: String) {
    #expect(link("\(scheme)://toggle")?.action == .perform(.playPause))
    #expect(link("\(scheme)://play")?.action == .command(.play))
    #expect(link("\(scheme)://pause")?.action == .command(.pause))
    #expect(link("\(scheme)://next")?.action == .perform(.nextTrack))
    #expect(link("\(scheme)://previous")?.action == .perform(.previousTrack))
    #expect(link("\(scheme)://expand")?.action == .perform(.openNotch))
    #expect(link("\(scheme)://seek?seconds=90")?.action == .command(.seek(to: 90)))
    #expect(link("\(scheme)://volume?percent=40")?.action == .setVolume(0.4))
    #expect(link("\(scheme)://settings") == .settings(section: nil))
    #expect(link("\(scheme)://settings?section=shortcuts") == .settings(section: "shortcuts"))
    #expect(link("\(scheme)://settings")?.action == nil)
}

@Test func anUnknownRouteOrSectionParsesToNothing() {
    #expect(link("warble://nonsense") == nil)
    #expect(link("warble://settings?section=nonsense") == nil)
    #expect(link("warble://") == nil)
    #expect(link("https://example.com/toggle") == nil)
    #expect(link("shot://toggle") == nil)
}

@Test func aBadValueParsesToNothing() {
    #expect(link("warble://seek") == nil)
    #expect(link("warble://seek?seconds=soon") == nil)
    #expect(link("warble://seek?seconds=-5") == nil)
    #expect(link("warble://seek?seconds=nan") == nil)
    #expect(link("warble://volume") == nil)
    #expect(link("warble://volume?percent=101") == nil)
    #expect(link("warble://volume?percent=-1") == nil)
    #expect(link("warble://volume?percent=loud") == nil)
}

@Test func theSchemeAndRouteIgnoreCase() {
    #expect(link("WARBLE://Toggle") == .toggle)
}

@Test func linksAreOffByDefault() {
    #expect(!AppState().answersLinks)
}

@Test func aLinkDoesWhatTheButtonDoesWhileLinksAreOn() {
    var state = AppState(answersLinks: true)
    _ = reduce(&state, .playbackReported(song), now: start)
    let effects = reduce(&state, .linkOpened(.toggle), now: start)
    #expect(effects.contains(.send(.togglePlayPause)))
    #expect(state.playback?.isPlaying == false)
    #expect(reduce(&state, .linkOpened(.volume(percent: 25)), now: start) == [.setVolume(0.25)])
    #expect(reduce(&state, .linkOpened(.seek(seconds: 60)), now: start).contains(.send(.seek(to: 60))))
    #expect(reduce(&state, .linkOpened(.next), now: start) == [.send(.nextTrack)])
}

@Test func expandOpensTheNotchWithTheKeyboard() {
    var state = AppState(answersLinks: true)
    #expect(reduce(&state, .linkOpened(.expand), now: start) == [.toggleKeyboard])
}

@Test func settingsAsksToOpenSettingsOnItsSection() {
    var state = AppState(answersLinks: true)
    #expect(reduce(&state, .linkOpened(.settings(section: "shortcuts")), now: start) == [.openSettings(section: "shortcuts")])
    #expect(reduce(&state, .linkOpened(.settings(section: nil)), now: start) == [.openSettings(section: nil)])
}

@Test func withLinksOffALinkChangesNothing() {
    var state = AppState()
    _ = reduce(&state, .playbackReported(song), now: start)
    let before = state
    for command: RemoteCommand in [.toggle, .play, .next, .expand, .seek(seconds: 5), .volume(percent: 10), .settings(section: "about")] {
        #expect(reduce(&state, .linkOpened(command), now: start).isEmpty)
    }
    #expect(state == before)
}

@Test func turningLinksOffStopsThem() {
    var state = AppState(answersLinks: true)
    _ = reduce(&state, .linksChanged(false), now: start)
    #expect(reduce(&state, .linkOpened(.expand), now: start).isEmpty)
    _ = reduce(&state, .linksChanged(true), now: start)
    #expect(reduce(&state, .linkOpened(.expand), now: start) == [.toggleKeyboard])
}

@Test func aLinkWithNothingPlayingGuessesNothingAndSetsNoTimer() {
    var state = AppState(answersLinks: true)
    // The command still goes to the source, but with nothing playing there is no state to guess and no deadline.
    #expect(reduce(&state, .linkOpened(.toggle), now: start) == [.send(.togglePlayPause)])
    #expect(state.playback == nil)
    #expect(state.deadline == nil)
}
