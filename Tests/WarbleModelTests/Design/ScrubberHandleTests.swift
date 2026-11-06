import Foundation
import Testing
@testable import WarbleModel

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
}

@Test func atRestTheHandleIsJustTheBarsRoundedTip() {
    let handle = ScrubberHandle(fraction: 0.5, width: 200, grown: 0)
    #expect(handle.radius == ScrubberHandle.barHeight / 2)
    #expect(handle.centre == 100)
    #expect(handle.fillet == nil)
}

@Test func withThePointerOverTheBarTheKnobIsFullSize() {
    let handle = ScrubberHandle(fraction: 0.5, width: 200, grown: 1)
    #expect(handle.radius == ScrubberHandle.knobDiameter / 2)
    #expect(handle.fillet != nil)
}

@Test func theKnobGrowsSmoothlyBetweenRestAndFull() {
    let half = ScrubberHandle(fraction: 0.5, width: 200, grown: 0.5).radius
    #expect(half > ScrubberHandle.barHeight / 2)
    #expect(half < ScrubberHandle.knobDiameter / 2)
}

@Test(arguments: [0.0, 1.0])
func theKnobStaysInsideTheBarAtEitherEnd(_ fraction: Double) {
    for grown in [0.0, 0.5, 1.0] {
        let handle = ScrubberHandle(fraction: fraction, width: 200, grown: grown)
        #expect(handle.centre - handle.radius >= 0)
        #expect(handle.centre + handle.radius <= 200)
    }
}

@Test func theCurveLeavesTheBarsEdgeAndMeetsTheKnobsEdge() throws {
    let handle = ScrubberHandle(fraction: 0.6, width: 200, grown: 1)
    let fillet = try #require(handle.fillet)
    #expect(fillet.start.y == -ScrubberHandle.barHeight / 2)
    #expect(fillet.start.x < handle.centre - handle.radius)
    #expect(abs(distance(fillet.end, CGPoint(x: handle.centre, y: 0)) - handle.radius) < 0.001)
    // It meets the knob above the bar, so it fills the corner the dip used to be in.
    #expect(fillet.end.y < -ScrubberHandle.barHeight / 2)
}

@Test func theCurveRunsAlongTheBarThenAlongTheKnob() throws {
    let handle = ScrubberHandle(fraction: 0.6, width: 200, grown: 1)
    let fillet = try #require(handle.fillet)
    // Leaving the bar, the first control point lies on the bar's edge, so there is no kink.
    #expect(abs(fillet.control1.y - fillet.start.y) < 0.001)
    #expect(fillet.control1.x > fillet.start.x)
    // Arriving, the last leg is at right angles to the knob's radius, so it's tangent to the knob.
    let radial = CGPoint(x: fillet.end.x - handle.centre, y: fillet.end.y)
    let leg = CGPoint(x: fillet.end.x - fillet.control2.x, y: fillet.end.y - fillet.control2.y)
    #expect(abs(radial.x * leg.x + radial.y * leg.y) < 0.001)
}

@Test func aKnobAtTheVeryStartHasNoCurve() {
    #expect(ScrubberHandle(fraction: 0, width: 200, grown: 1).fillet == nil)
}

@Test func aBarNarrowerThanTheKnobCentresIt() {
    let handle = ScrubberHandle(fraction: 0.9, width: 6, grown: 1)
    #expect(handle.centre == 3)
}

@Test func theTimeUnderThePointerRunsFromTheStartOfTheTrackToItsEnd() {
    #expect(ScrubberHandle.time(atX: 0, width: 200, duration: 180) == 0)
    #expect(ScrubberHandle.time(atX: 100, width: 200, duration: 180) == 90)
    #expect(ScrubberHandle.time(atX: 200, width: 200, duration: 180) == 180)
}

@Test func aPointerPastEitherEndOfTheBarReadsAsThatEnd() {
    #expect(ScrubberHandle.time(atX: -30, width: 200, duration: 180) == 0)
    #expect(ScrubberHandle.time(atX: 260, width: 200, duration: 180) == 180)
    #expect(ScrubberHandle.fraction(atX: 50, width: 0) == 0)
}

@Test func theLabelOverTheBarReadsLikeTheElapsedTime() {
    #expect(ScrubberHandle.timeLabel(atX: 0, width: 200, duration: 187) == "0:00")
    #expect(ScrubberHandle.timeLabel(atX: 100, width: 200, duration: 187) == "1:33")
    #expect(ScrubberHandle.timeLabel(atX: 200, width: 200, duration: 187) == "3:07")
    #expect(ScrubberHandle.timeLabel(atX: 150, width: 200, duration: 4964) == "1:02:03")
}

@Test func aTrackWithNoKnownLengthHasNoTimeUnderThePointer() {
    #expect(ScrubberHandle.time(atX: 100, width: 200, duration: nil) == nil)
    #expect(ScrubberHandle.timeLabel(atX: 100, width: 200, duration: 0) == nil)
}
