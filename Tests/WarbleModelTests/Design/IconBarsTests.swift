#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import WarbleModel

@Test func iconBarsAreMediumTallThenShortOnOneBaseline() {
    let bars = IconBars.rects
    #expect(bars.count == 3)
    #expect(bars[2].height < bars[0].height && bars[0].height < bars[1].height)
    #expect(Set(bars.map(\.minY)).count == 1)
    #expect(bars.map(\.maxY).max() == bars[IconBars.accent].maxY)
}

@Test func scaledIconBarsKeepTheirHeightsAndSitOnWholePoints() {
    let bars = IconBars.rects(height: 16)
    #expect(bars.map(\.height).max() == 16)
    for (scaled, bar) in zip(bars, IconBars.rects) {
        #expect(abs(scaled.height / 16 - bar.height / IconBars.rects[1].height) < 0.0001)
        #expect(scaled.minY == 0)
        #expect(scaled.minX == scaled.minX.rounded() && scaled.width == scaled.width.rounded())
    }
    #expect(bars[0].minX == 0)
    #expect(bars[1].minX - bars[0].maxX == bars[2].minX - bars[1].maxX)
    #expect(bars.last!.maxX == 16)
}

@Test func tinyIconBarsStillHaveAWidthAndAGap() {
    let bars = IconBars.rects(height: 2)
    #expect(bars.allSatisfy { $0.width >= 1 })
    #expect(bars[1].minX - bars[0].maxX >= 1)
}
