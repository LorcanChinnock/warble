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
            send(.sourceReported(bundleIdentifier: "app", playing))
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
    run.send(.sourceReported(bundleIdentifier: "app", nil))
    run.send(.command(.togglePlayPause))
    #expect(run.state.playback == song)
    #expect(run.state.hideAt != nil)
    #expect(run.effects == [.send(.togglePlayPause)])
}

@Test func openAppOpensTheOneThatsPlayingOrElseTheLastPlayed() {
    var run = Run()
    run.send(.openApp)
    #expect(run.effects == [.openApp(bundleIdentifier: "com.apple.Music")])
    var idle = Run(playing: nil)
    idle.send(.openApp)
    #expect(idle.effects.isEmpty)
    idle.send(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.spotify.client", title: "Old")))
    idle.send(.openApp)
    #expect(idle.effects == [.openApp(bundleIdentifier: "com.spotify.client")])
}

@Test func resumingTheLastTrackPlaysTheSessionWhileTheAppStillHasOne() {
    var run = Run()
    run.send(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.apple.Music", title: "Old")))
    run.send(.resumeLastPlayed)
    #expect(run.effects == [.send(.play)])
}

@Test func resumingTheLastTrackWithNoSessionOpensItsLinkOrElseItsApp() {
    var run = Run(playing: nil)
    run.send(.resumeLastPlayed)
    #expect(run.effects.isEmpty)
    run.send(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.google.Chrome", title: "Video")))
    run.send(.resumeLastPlayed)
    #expect(run.effects == [.openApp(bundleIdentifier: "com.google.Chrome")])
    var spotify = Run(playing: nil)
    let link = URL(string: "https://open.spotify.com/track/abc123")
    spotify.send(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.spotify.client", title: "Song", link: link)))
    spotify.send(.resumeLastPlayed)
    #expect(spotify.effects == [.openLink(URL(string: "spotify:track:abc123")!)])
}

@Test func resumingATabOpensItsAddressInTheBrowserItPlayedIn() {
    var run = Run(playing: nil)
    let address = URL(string: "https://www.youtube.com/watch?v=abc")!
    run.send(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.google.Chrome", title: "Video", link: address)))
    run.send(.resumeLastPlayed)
    #expect(run.effects == [.openLink(address, in: "com.google.Chrome")])
}

@Test func resumingSpotifyAfterItQuitLaunchesItAndPlaysWhenThereIsNoLink() {
    var run = Run(playing: nil)
    run.send(.lastPlayedLoaded(LastPlayed(bundleIdentifier: "com.spotify.client", title: "Song")))
    run.send(.resumeLastPlayed)
    #expect(run.effects == [.launchAndPlay(.spotify)])
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

@Test func theArrowKeysChangeTheVolume() {
    var run = Run()
    run.send(.volumeKey(delta: 0.1, volume: 0.5, isMuted: false))
    #expect(run.effects == [.setVolume(NotchKey.volume(changing: 0.5, by: 0.1))])
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

// MARK: Last played

@Test func aNewTrackOrNewArtIsRememberedButAPauseOrSeekIsnt() {
    var run = Run(playing: nil)
    run.send(.sourceReported(bundleIdentifier: "app", song))
    #expect(run.effects == [.remember(song, pass: 1)])
    run.send(.sourceReported(bundleIdentifier: "app", song.playing(false, at: start + 5)))
    run.send(.sourceReported(bundleIdentifier: "app", song.seeked(to: 50, at: start + 6)))
    #expect(run.effects.count == 1)
    var withArt = song
    withArt.artwork = Data([1, 2, 3])
    run.send(.sourceReported(bundleIdentifier: "app", withArt))
    #expect(run.effects.last == .remember(withArt, pass: 2))
}

@Test func aRememberedTrackIsShownAndSavedUnlessANewerOneHasBegun() {
    var run = Run(playing: nil)
    run.send(.sourceReported(bundleIdentifier: "app", song))
    var next = song
    next.title = "Next"
    run.send(.sourceReported(bundleIdentifier: "app", next))
    run.effects = []
    // The first track's art finished shrinking after the next began.
    run.send(.remembered(LastPlayed(bundleIdentifier: song.bundleIdentifier, title: "Song"), pass: 1))
    #expect(run.state.lastPlayed == nil)
    #expect(run.effects.isEmpty)
    let latest = LastPlayed(bundleIdentifier: song.bundleIdentifier, title: "Next")
    run.send(.remembered(latest, pass: 2))
    #expect(run.state.lastPlayed == latest)
    #expect(run.effects == [.saveLastPlayed(latest)])
}

@Test func artArrivingKeepsTheAddressFoundWhenTheTabStarted() {
    let found = URL(string: "https://example.com/watch?v=1")
    let tab = PlaybackState(bundleIdentifier: "com.google.Chrome", title: "Video", elapsedTimestamp: start, rate: 1)
    var run = Run(playing: nil)
    run.send(.sourceReported(bundleIdentifier: "app", tab))
    run.send(.remembered(LastPlayed(bundleIdentifier: tab.bundleIdentifier, title: "Video", link: found), pass: 1))
    var withArt = tab
    withArt.artwork = Data([1])
    run.send(.sourceReported(bundleIdentifier: "app", withArt))
    // The tab's title no longer names the track by then, so the second look finds no address.
    run.send(.remembered(LastPlayed(bundleIdentifier: tab.bundleIdentifier, title: "Video", artwork: Data([1])), pass: 2))
    #expect(run.state.lastPlayed?.link == found)
    #expect(run.state.lastPlayed?.artwork == Data([1]))
}

@Test func theSavedTrackLoadsOnlyIfNothingHasPlayedSince() {
    let saved = LastPlayed(bundleIdentifier: "com.apple.Music", title: "Saved")
    var fresh = Run(playing: nil)
    fresh.send(.lastPlayedLoaded(saved))
    #expect(fresh.state.lastPlayed == saved)
    var played = Run()
    played.send(.lastPlayedLoaded(saved))
    #expect(played.state.lastPlayed == nil)
}

@MainActor
@Test func theRunnerShrinksTheArtAndAnswersWithItsPass() async {
    let runner = makeRunner()
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.appName = { _ in "Music" }
    runner.perform(.remember(song, pass: 3))
    await runner.finish()
    #expect(dispatched == [.remembered(LastPlayed(bundleIdentifier: song.bundleIdentifier, appName: "Music", title: "Song", artist: "Artist"), pass: 3)])
}

@MainActor
@Test func aTrackThatStartedInABrowserIsRememberedWithItsTabAndNoOtherIs() async {
    let runner = makeRunner()
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.tabLink = { _, title in URL(string: "https://example.com/\(title)") }
    let tab = PlaybackState(bundleIdentifier: "com.google.Chrome", title: "Video", elapsedTimestamp: start, rate: 1)
    runner.perform(.remember(tab, pass: 1))
    runner.perform(.remember(song, pass: 2))
    await runner.finish()
    let links = dispatched.compactMap { action -> URL?? in
        if case .remembered(let track, _) = action { .some(track.link) } else { nil }
    }
    #expect(links.contains { $0 == URL(string: "https://example.com/Video") })
    #expect(links.filter { $0 == nil }.count == 1)
}

@MainActor
@Test func theLatestSaveWins() async {
    let store = FakeLastPlayed()
    let runner = makeRunner(lastPlayed: store)
    let first = LastPlayed(bundleIdentifier: "com.apple.Music", title: "First")
    let second = LastPlayed(bundleIdentifier: "com.apple.Music", title: "Second")
    runner.perform(.saveLastPlayed(first))
    runner.perform(.saveLastPlayed(second))
    await runner.finish()
    #expect(store.saved == [first, second])
}

@MainActor
@Test func theRunnerLoadsTheSavedTrack() async {
    let store = FakeLastPlayed()
    store.stored = LastPlayed(bundleIdentifier: "com.apple.Music", title: "Saved")
    let runner = makeRunner(lastPlayed: store)
    var dispatched: [AppAction] = []
    runner.dispatch = { dispatched.append($0) }
    runner.loadLastPlayed()
    await runner.finish()
    #expect(dispatched == [.lastPlayedLoaded(store.stored)])
}
