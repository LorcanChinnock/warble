#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import WarbleModel

/// A 14-inch MacBook Pro's notch at "More Space": half-point height and origin.
private let notch = CGRect(x: 856, y: 1205.5, width: 208, height: 37.5)

@Test func nothingIsDrawnWhenHidden() {
    #expect(NotchLayout.frame(.hidden, notch: notch) == nil)
}

@Test func restingWidensTheNotchEquallyOnBothSides() throws {
    let frame = try #require(NotchLayout.frame(.resting, notch: notch))
    #expect(frame == CGRect(x: 806, y: 1205.5, width: 308, height: 37.5))
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

@Test func onlyTheHousingCountsAsOnTheNotchWhileResting() throws {
    #expect(NotchLayout.hoverArea(.hidden, notch: notch) == nil)
    #expect(NotchLayout.hoverArea(.resting, notch: notch) == notch)
    #expect(NotchLayout.hoverArea(.expanded, notch: notch) == NotchLayout.frame(.expanded, notch: notch))
}

@Test func hoverStatesMapToTheShapesTheyDraw() {
    #expect(NotchState(.resting) == .resting)
    #expect(NotchState(.expanded) == .expanded)
    #expect(NotchState(.pinned) == .expanded)
}
