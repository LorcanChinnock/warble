import Foundation
import Testing
@testable import WarbleModel

@Test func aWheelClickMovesTheVolumeAsFarAsAVolumeKey() {
    #expect(VolumeScroll.volume(after: 1, from: 0.5, precise: false, inverted: false) == 0.5625)
    #expect(VolumeScroll.volume(after: -1, from: 0.5, precise: false, inverted: false) == 0.4375)
}

@Test func aTrackpadMovesTheVolumeByPoints() {
    #expect(VolumeScroll.volume(after: 40, from: 0.5, precise: true, inverted: false) == 0.6)
}

@Test func fingersMovingUpRaiseTheVolumeWithNaturalScrolling() {
    // Natural scrolling reports fingers moving up as a negative delta.
    #expect(VolumeScroll.volume(after: -40, from: 0.5, precise: true, inverted: true) == 0.6)
    #expect(VolumeScroll.volume(after: 40, from: 0.5, precise: true, inverted: true) == 0.4)
}

@Test func theVolumeStaysBetweenSilentAndFull() {
    #expect(VolumeScroll.volume(after: 1000, from: 0.9, precise: true, inverted: false) == 1)
    #expect(VolumeScroll.volume(after: -1000, from: 0.1, precise: true, inverted: false) == 0)
}

@Test func passingATenthTicks() {
    #expect(VolumeScroll.crossesTick(from: 0.29, to: 0.31))
    #expect(VolumeScroll.crossesTick(from: 0.31, to: 0.29))
    #expect(VolumeScroll.crossesTick(from: 0.29, to: 0.3))
    #expect(VolumeScroll.crossesTick(from: 0.99, to: 1))
    #expect(VolumeScroll.crossesTick(from: 0.05, to: 0.25))
}

@Test func movingWithinATenthDoesntTick() {
    #expect(!VolumeScroll.crossesTick(from: 0.31, to: 0.39))
    #expect(!VolumeScroll.crossesTick(from: 0.5, to: 0.5))
    #expect(!VolumeScroll.crossesTick(from: 1, to: 1))
    #expect(!VolumeScroll.crossesTick(from: 0, to: 0))
}

@Test func aTenthReadBackSlightlyLowStillCountsAsThatTenth() {
    #expect(!VolumeScroll.crossesTick(from: 0.29999, to: 0.32))
}
