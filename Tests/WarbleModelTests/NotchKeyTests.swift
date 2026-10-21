import Foundation
import Testing
@testable import WarbleModel

@Test func theNotchKeysPlaySeekSkipChangeTheVolumeAndClose() {
    #expect(NotchKey(keyCode: 49, modifiers: 0) == .command(.togglePlayPause))
    #expect(NotchKey(keyCode: 123, modifiers: 0) == .seek(by: -10))
    #expect(NotchKey(keyCode: 124, modifiers: 0) == .seek(by: 10))
    #expect(NotchKey(keyCode: 123, modifiers: KeyCombo.shift) == .command(.previousTrack))
    #expect(NotchKey(keyCode: 124, modifiers: KeyCombo.shift) == .command(.nextTrack))
    #expect(NotchKey(keyCode: 126, modifiers: 0) == .volume(by: 1.0 / 16))
    #expect(NotchKey(keyCode: 125, modifiers: 0) == .volume(by: -1.0 / 16))
    #expect(NotchKey(keyCode: 53, modifiers: 0) == .close)
}

@Test func otherKeysAndModifiersAreLeftForTheFocusedControl() {
    // Tab, Return and a letter.
    #expect(NotchKey(keyCode: 48, modifiers: 0) == nil)
    #expect(NotchKey(keyCode: 36, modifiers: 0) == nil)
    #expect(NotchKey(keyCode: 0, modifiers: 0) == nil)
    #expect(NotchKey(keyCode: 124, modifiers: KeyCombo.command) == nil)
    #expect(NotchKey(keyCode: 124, modifiers: KeyCombo.shift | KeyCombo.option) == nil)
    #expect(NotchKey(keyCode: 49, modifiers: KeyCombo.shift) == nil)
    #expect(NotchKey(keyCode: 53, modifiers: KeyCombo.shift) == nil)
}

@Test func seekingByKeyStaysWithinTheTrack() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let track = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Song", duration: 200, elapsed: 5, elapsedTimestamp: now, rate: 1)
    #expect(NotchKey.position(seeking: -10, in: track, at: now) == 0)
    #expect(NotchKey.position(seeking: 10, in: track, at: now + 3) == 18)
    #expect(NotchKey.position(seeking: 10, in: track, at: now + 190) == 200)
}

@Test func aLiveStreamHasNoPositionToSeekTo() {
    let stream = PlaybackState(bundleIdentifier: "com.apple.Music", title: "Radio", elapsed: 30, elapsedTimestamp: .now, rate: 1)
    #expect(NotchKey.position(seeking: 10, in: stream, at: .now) == nil)
}

@Test func volumeByKeyStopsAtSilentAndFull() {
    #expect(NotchKey.volume(changing: 0.5, by: NotchKey.volumeStep) == 0.5625)
    #expect(NotchKey.volume(changing: 0.98, by: NotchKey.volumeStep) == 1)
    #expect(NotchKey.volume(changing: 0.02, by: -NotchKey.volumeStep) == 0)
}
