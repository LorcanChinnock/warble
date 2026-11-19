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

@Test func playAgainCardPartsRiseOneAfterAnotherAfterTheContentStartsToShow() {
    let delays = (0..<3).map { NotchMotion.recallDelay($0) }
    #expect(delays[0] >= NotchMotion.contentDelay)
    #expect(delays == delays.sorted() && Set(delays).count == 3)
    #expect((0..<3).allSatisfy { NotchMotion.recallDelay($0, reduceMotion: true) == NotchMotion.contentDelay })
}

@Test func theHeartAndPlayIconOnlyGrowAndStayWithinTheirRows() {
    #expect(NotchMotion.heartPopScale > 1 && NotchMotion.heartPopScale <= 1.4)
    #expect(NotchMotion.playHoverScale > 1 && NotchMotion.playHoverScale <= 1.3)
    #expect(NotchMotion.heartAppearScale > 0 && NotchMotion.heartAppearScale < 1)
    #expect(NotchMotion.dotScale > 0 && NotchMotion.dotScale < 1)
    #expect(NotchMotion.riseDistance > 0 && NotchMotion.riseDistance <= 8)
}
