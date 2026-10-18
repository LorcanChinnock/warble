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
