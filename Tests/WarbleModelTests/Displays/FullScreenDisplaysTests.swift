import Foundation
import Testing
@testable import WarbleModel

private func display(_ id: String, spaceType: Int?) -> [String: Any] {
    var display: [String: Any] = ["Display Identifier": id]
    if let spaceType {
        display["Current Space"] = ["type": spaceType]
    }
    return display
}

@Test func aDisplayInAFullScreenSpaceShowsAFullScreenApp() {
    let spaces = [display("A", spaceType: 4), display("B", spaceType: 0)]
    #expect(FullScreenDisplays.from(spaces: spaces, allDisplays: ["A", "B"]) == ["A"])
}

@Test func desktopsShowNoFullScreenApp() {
    #expect(FullScreenDisplays.from(spaces: [display("A", spaceType: 0)], allDisplays: ["A"]).isEmpty)
}

@Test func aSharedSpaceInFullScreenCoversEveryDisplay() {
    #expect(FullScreenDisplays.from(spaces: [display("Main", spaceType: 4)], allDisplays: ["A", "B"]) == ["A", "B"])
}

@Test func aSharedDesktopCoversNoDisplay() {
    #expect(FullScreenDisplays.from(spaces: [display("Main", spaceType: 0)], allDisplays: ["A", "B"]).isEmpty)
}

@Test func entriesWithoutASpaceOrAnIdentifierAreSkipped() {
    let spaces: [[String: Any]] = [display("A", spaceType: nil), ["Current Space": ["type": 4]]]
    #expect(FullScreenDisplays.from(spaces: spaces, allDisplays: ["A"]).isEmpty)
}

@Test func noSpacesMeansNoFullScreenApps() {
    #expect(FullScreenDisplays.from(spaces: [], allDisplays: ["A"]).isEmpty)
}
