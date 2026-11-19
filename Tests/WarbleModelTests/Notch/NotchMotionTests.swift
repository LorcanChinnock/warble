import Foundation
import Testing
@testable import WarbleModel

@Test func theBarsRiseOneAfterAnotherFiftyMillisecondsApart() {
    let delays = (0..<4).map { NotchMotion.barDelay($0) }
    #expect(delays.map { ($0 * 1000).rounded() } == [160, 210, 260, 310])
}

@Test func theBarsRiseOnlyOnceTheArtHasStartedToShow() {
    #expect(NotchMotion.barDelay(0) > NotchMotion.contentDelay)
    #expect(NotchMotion.barDelay(0) > NotchMotion.artDelay)
}

@Test func theArtStartsToGrowAsTheShapeOpensAndGrowsFromSixtyPercent() {
    #expect(NotchMotion.artDelay < NotchMotion.morph)
    #expect(NotchMotion.artScale == 0.6)
}

@Test func theBarsStartMovingOnceTheLastHasRisen() {
    #expect(abs(NotchMotion.barsRisen(count: 4) - 0.57) < 0.0001)
    #expect(NotchMotion.barsRisen(count: 0) == 0)
}

@Test func withReduceMotionTheBarsShowAtOnce() {
    #expect((0..<4).allSatisfy { NotchMotion.barDelay($0, reduceMotion: true) == 0 })
    #expect(NotchMotion.barsRisen(count: 4, reduceMotion: true) == 0)
}

@Test func theContentAndTheBarsAreGoneBeforeTheShapeHasClosedOverThem() {
    #expect(NotchMotion.contentOut < NotchMotion.morph)
    #expect(NotchMotion.barDrop < NotchMotion.morph)
}

@Test func theContentFinishesFadingInSoonAfterTheShapeHasOpened() {
    #expect(NotchMotion.contentDelay + NotchMotion.contentIn < NotchMotion.morph + 0.1)
}

@Test func trackChangeLinesSlideInOneAfterAnotherAndTogetherWithReduceMotion() {
  let starts = (0..<3).map { NotchMotion.trackLineStart($0) }
  #expect(starts == starts.sorted() && Set(starts).count == 3)
  #expect((0..<3).allSatisfy { NotchMotion.trackLineStart($0, reduceMotion: true) == 0 })
}

@Test func trackChangeArtShrinksBackAndItsOvershootStaysSmall() {
  #expect(NotchMotion.trackArtScale < 1 && NotchMotion.trackArtScale > 0.8)
  #expect(NotchMotion.trackArtSpringBounce > 0 && NotchMotion.trackArtSpringBounce < 0.4)
  #expect(NotchMotion.trackLineOut < NotchMotion.trackLineIn)
}

@Test func aPressedButtonShrinksQuicklyAndOnlyALittle() {
    #expect(NotchMotion.pressScale < 1 && NotchMotion.pressScale > 0.8)
    #expect(NotchMotion.pressDown < 0.12)
    #expect(NotchMotion.pressNudge > 0 && NotchMotion.pressNudge < 6)
}

@Test func aReleasedButtonSpringsBackWithAnOvershootAndSettlesWithinTheMorph() {
    #expect(NotchMotion.pressReleaseDamping < 1)
    #expect(NotchMotion.pressReleaseResponse < NotchMotion.morph + 0.1)
    #expect(NotchMotion.symbolSwap <= NotchMotion.morph)
}

@Test func volumeAndSpeakerChangesAreShorterThanTheMorph() {
    #expect(NotchMotion.volumeEase < NotchMotion.morph)
    #expect(NotchMotion.statusSymbolSwap < NotchMotion.morph)
}
