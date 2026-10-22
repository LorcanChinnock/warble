#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import WarbleModel

private let builtIn = CGRect(x: -1512, y: 0, width: 1512, height: 982)

@Test func menuBarHeightIsTheMenuBarOrTheNotch() {
    let visible = CGRect(x: -1512, y: 0, width: 1512, height: 950)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: visible, safeAreaTop: 32) == 32)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: builtIn, safeAreaTop: 32) == 32)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: visible, safeAreaTop: 0) == 32)
    #expect(MenuBar.height(screenFrame: builtIn, visibleFrame: builtIn, safeAreaTop: 0) == 0)
}

@Test func frameBelowDropsTheTopStrip() {
    #expect(MenuBar.frameBelow(screenFrame: builtIn, height: 32) == CGRect(x: -1512, y: 0, width: 1512, height: 950))
}

@Test func notchSitsBetweenTheMenuBarAreas() {
    let left = CGRect(x: -1512, y: 950, width: 663, height: 32)
    let right = CGRect(x: -664, y: 950, width: 664, height: 32)
    #expect(MenuBar.notch(safeAreaTop: 32, leftArea: left, rightArea: right) == CGRect(x: -849, y: 950, width: 185, height: 32))
    #expect(MenuBar.notch(safeAreaTop: 0, leftArea: left, rightArea: right) == nil)
    #expect(MenuBar.notch(safeAreaTop: 32, leftArea: nil, rightArea: nil) == nil)
}

@Test(arguments: fifteenInchAir)
func theHousingIsTheSameHardwareAtEveryScale(_ scale: MeasuredScale) throws {
    let notch = try #require(MenuBar.notch(safeAreaTop: scale.safeAreaTop, leftArea: scale.leftArea, rightArea: scale.rightArea))
    let pixels = scale.pixelsPerPoint
    // Each edge is within the quarter point macOS rounds to, and the height up to half a point over, never under.
    #expect(abs(notch.minX * pixels - 1284) <= 0.25 * pixels)
    #expect(abs(notch.maxX * pixels - 1596) <= 0.25 * pixels)
    #expect(notch.height * pixels >= 56)
    #expect(notch.height * pixels - 56 <= 0.5 * pixels)
    #expect(notch.maxY == scale.screen.height)
    // Centred on a whole point, so a window grown out to whole points stays centred on it.
    #expect(notch.midX == scale.screen.width / 2)
}
