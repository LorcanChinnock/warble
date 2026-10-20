#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import WarbleModel

/// A 14-inch MacBook Pro at its default size, with its notch.
private let builtIn = NotchDisplay(
    id: "built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 32,
    notch: CGRect(x: 663, y: 950, width: 185, height: 32), isMain: true
)
/// A 27-inch display to the right of it, without a notch.
private let external = NotchDisplay(
    id: "external", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), menuBarHeight: 24, notch: nil, isMain: false
)

private func main(_ display: NotchDisplay) -> NotchDisplay {
    var display = display
    display.isMain = true
    return display
}

@Test func theVirtualHousingSitsAtTheTopCentreAsTallAsTheMenuBar() {
    let housing = VirtualNotch.housing(in: external.frame, menuBarHeight: 24)
    #expect(housing == CGRect(x: 2712, y: 1416, width: 160, height: 24))
    #expect(housing.midX == external.frame.midX)
    #expect(housing.maxY == external.frame.maxY)
}

@Test func theVirtualHousingStartsOnAWholePoint() {
    let odd = CGRect(x: 0, y: 0, width: 1365, height: 768)
    #expect(VirtualNotch.housing(in: odd, menuBarHeight: 24).minX == 603)
}

@Test func aHiddenMenuBarStillGetsAHousingOfMenuBarHeight() {
    #expect(VirtualNotch.housing(in: external.frame, menuBarHeight: 0).height == 24)
}

@Test func onlyTheRealNotchShowsByDefaultWithTheLidOpen() throws {
    let notch = try #require(builtIn.notch)
    #expect(VirtualNotch.housings([builtIn, external], rules: [:]) == [NotchHousing(display: "built-in", frame: notch, isVirtual: false)])
}

@Test func theMainDisplayTakesOverWhenTheLidCloses() {
    let housings = VirtualNotch.housings([main(external)], rules: [:])
    #expect(housings == [NotchHousing(display: "external", frame: CGRect(x: 2712, y: 1416, width: 160, height: 24), isVirtual: true)])
}

@Test func aMacWithoutANotchDrawsOneOnItsMainDisplay() {
    var air = builtIn
    air.notch = nil
    let housings = VirtualNotch.housings([air, external], rules: [:])
    #expect(housings.map(\.display) == ["built-in"])
    #expect(housings.map(\.isVirtual) == [true])
}

@Test func otherDisplaysDrawNothingUntilTheyreGivenARule() {
    var second = external
    second.id = "second"
    #expect(VirtualNotch.housings([main(external), second], rules: [:]).map(\.display) == ["external"])
}

@Test func alwaysShowsBesideTheRealNotch() {
    let housings = VirtualNotch.housings([builtIn, external], rules: ["external": .always])
    #expect(housings.map(\.display) == ["built-in", "external"])
    #expect(housings.map(\.isVirtual) == [false, true])
}

@Test func offHidesTheMainDisplayEvenWithTheLidClosed() {
    #expect(VirtualNotch.housings([main(external)], rules: ["external": .off]).isEmpty)
}

@Test func aRuleNeverHidesARealNotch() {
    #expect(VirtualNotch.housings([builtIn], rules: ["built-in": .off]).count == 1)
}

@Test func onlyTheMainDisplayStandsInForTheNotchByDefault() {
    #expect(VirtualNotchRule.default(isMain: true) == .noNotch)
    #expect(VirtualNotchRule.default(isMain: false) == .off)
}
