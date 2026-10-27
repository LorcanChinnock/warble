import Foundation
import Testing
@testable import WarbleModel

@Test func aPreviewKeptAfterPausingEndsOnThePausedSong() {
    #expect(PreviewEnding(pauseDelay: .always, visibility: .whenPlaying) == .paused)
    #expect(PreviewEnding(pauseDelay: .always, visibility: .always) == .paused)
}

@Test func aPreviewThatGoesQuietKeepsAnEmptyNotchOnlyWhenTheNotchStaysAlways() {
    for delay in [PauseDelay.tenSeconds, .oneMinute] {
        #expect(PreviewEnding(pauseDelay: delay, visibility: .always) == .emptyNotch)
        #expect(PreviewEnding(pauseDelay: delay, visibility: .whenPlaying) == .bareScreen)
    }
}

@Test func aPreviewWithTheVirtualNotchOffEndsOnTheBareScreen() {
    for delay in PauseDelay.allCases {
        #expect(PreviewEnding(pauseDelay: delay, visibility: .off) == .bareScreen)
    }
}
