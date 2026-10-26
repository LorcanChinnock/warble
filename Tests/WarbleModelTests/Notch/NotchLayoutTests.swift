#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import WarbleModel

/// A 15-inch MacBook Air's notch at More Space, 1920 × 1243: half-point height and origin.
private let notch = CGRect(x: 856, y: 1205.5, width: 208, height: 37.5)

@Test func nothingIsDrawnWhenHidden() {
    #expect(NotchLayout.frame(.hidden, notch: notch) == nil)
}

@Test func restingWidensTheNotchEquallyOnBothSides() throws {
    let frame = try #require(NotchLayout.frame(.resting, notch: notch))
    #expect(frame == CGRect(x: 818.5, y: 1205.5, width: 283, height: 37.5))
    #expect(frame.midX == notch.midX)
    // The panel covers the housing exactly top to bottom, so no sliver of menu bar shows above or below it.
    #expect(frame.minY == notch.minY)
    #expect(frame.maxY == notch.maxY)
}

@Test func expandedIsCentredOnTheNotchAndReachesFurtherDown() throws {
    let frame = try #require(NotchLayout.frame(.expanded, notch: notch))
    #expect(frame == CGRect(x: 786, y: 1045.5, width: 348, height: 197.5))
    #expect(frame.midX == notch.midX)
    #expect(frame.maxY == notch.maxY)
}

@Test func expandedWidensWithTheNotch() throws {
    let wide = CGRect(x: 840, y: 1205.5, width: 240, height: 37.5)
    let expanded = try #require(NotchLayout.frame(.expanded, notch: wide))
    #expect(expanded.width == 380)
    #expect(expanded.midX == wide.midX)
}

@Test func expandedContainsResting() throws {
    let resting = try #require(NotchLayout.frame(.resting, notch: notch))
    let expanded = try #require(NotchLayout.frame(.expanded, notch: notch))
    // So the panel only grows on the way open, and the shape morphs without jumping sideways.
    #expect(expanded.contains(resting))
}

@Test func idleCoversTheHousingExactly() {
    // Same frame as the housing, so nothing shows beyond it.
    #expect(NotchLayout.frame(.idle, notch: notch) == notch)
    #expect(NotchLayout.frame(.idle, notch: notch, card: .idle) == notch)
}

@Test func theIdleCardIsAsWideAsExpandedAndShorter() throws {
    let player = try #require(NotchLayout.frame(.expanded, notch: notch))
    let idle = try #require(NotchLayout.frame(.expanded, notch: notch, card: .idle))
    #expect(idle == CGRect(x: 786, y: 1129.5, width: 348, height: 113.5))
    #expect(idle.width == player.width)
    #expect(idle.midX == notch.midX)
    #expect(idle.maxY == notch.maxY)
    #expect(idle.height == notch.height + NotchLayout.idleDrop)
    #expect(idle.height < player.height)
    #expect(idle.contains(notch))
    // The card answers the pointer anywhere on it, so moving onto it from the housing keeps it open.
    #expect(NotchLayout.hoverArea(.expanded, notch: notch, card: .idle) == idle)
}

@Test func onlyTheHousingCountsAsOnTheNotchWhileIdleOrResting() throws {
    #expect(NotchLayout.hoverArea(.hidden, notch: notch) == nil)
    #expect(NotchLayout.hoverArea(.idle, notch: notch) == notch)
    #expect(NotchLayout.hoverArea(.resting, notch: notch) == notch)
    #expect(NotchLayout.hoverArea(.expanded, notch: notch) == NotchLayout.frame(.expanded, notch: notch))
}

@Test func hoverStatesMapToTheShapesTheyDraw() {
    #expect(NotchState(.resting) == .resting)
    #expect(NotchState(.expanded) == .expanded)
    #expect(NotchState(.pinned) == .expanded)
}

@Test func aRestingNotchOnlyDrawsWingsWithSomethingPlaying() {
    #expect(NotchState(.resting, isPlaying: true) == .resting)
    #expect(NotchState(.expanded, isPlaying: true) == .expanded)
    #expect(NotchState(.pinned, isPlaying: true) == .expanded)
    #expect(NotchState(.resting, isPlaying: false) == .idle)
}

@Test(arguments: fifteenInchAir)
func theCornersAreTheHousingsAtEveryScale(_ scale: MeasuredScale) throws {
    let notch = try #require(MenuBar.notch(safeAreaTop: scale.safeAreaTop, leftArea: scale.leftArea, rightArea: scale.rightArea))
    let pixels = scale.pixelsPerPoint
    // The same pixels whatever the text size, within what the height's rounding carries over.
    let radius = NotchLayout.cornerRadius(notch: notch) * pixels
    #expect(abs(radius - NotchLayout.cornerRatio * 56) <= NotchLayout.cornerRatio * 0.5 * pixels)
}

@Test(arguments: fifteenInchAir)
func eachWingHoldsItsContentWithTheSameMarginAllRound(_ scale: MeasuredScale) throws {
    let notch = try #require(MenuBar.notch(safeAreaTop: scale.safeAreaTop, leftArea: scale.leftArea, rightArea: scale.rightArea))
    let wing = NotchLayout.wing(notch: notch)
    let inset = NotchLayout.inset(notch: notch)
    let content = wing - 2 * inset
    // A square: the margin beside the content matches the margin above and below it.
    #expect(content + 2 * inset == notch.height)
    #expect(content > 0)
    let resting = try #require(NotchLayout.frame(.resting, notch: notch))
    #expect(notch.minX - resting.minX == wing)
    #expect(resting.maxX - notch.maxX == wing)
    #expect(resting.minY == notch.minY)
    #expect(resting.height == notch.height)
    let expanded = try #require(NotchLayout.frame(.expanded, notch: notch))
    #expect(expanded.contains(resting))
}

@Test(arguments: fifteenInchAir)
func theWindowCoversWholePointsAndStaysCentredOnTheHousing(_ scale: MeasuredScale) throws {
    let notch = try #require(MenuBar.notch(safeAreaTop: scale.safeAreaTop, leftArea: scale.leftArea, rightArea: scale.rightArea))
    for state in NotchState.allCases {
        let frame = NotchLayout.frame(state, notch: notch) ?? notch
        let window = NotchLayout.window(for: frame)
        #expect(window == window.integral)
        #expect(window.contains(frame))
        #expect(window.maxY == frame.maxY)
        // The shape is drawn in the middle of the window, so the window's middle has to be the housing's.
        #expect(window.midX == notch.midX)
    }
}

@Test func aWindowAtAHalfPointGrowsOnBothSides() {
    let notch = CGRect(x: 456.5, y: 643, width: 111, height: 20)
    #expect(NotchLayout.window(for: notch) == CGRect(x: 456, y: 643, width: 112, height: 20))
}
