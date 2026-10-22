import Testing
@testable import WarbleModel

private let outputs = [
    AudioOutput(id: 1, name: "MacBook Air Speakers", transport: .builtIn),
    AudioOutput(id: 2, name: "Lorcan's AirPods Pro", transport: .bluetooth),
    AudioOutput(id: 3, name: "Studio Display Speakers", transport: .displayPort),
    AudioOutput(id: 4, name: "Café", transport: .usb),
    AudioOutput(id: 5, name: "Studio", transport: .usb),
]

@Test func anExactNameWinsOverALongerOne() {
    #expect(outputs.matching("Studio")?.id == 5)
    #expect(outputs.matching("studio")?.id == 5)
}

@Test func theOnlyNameThatStartsWithItMatches() {
    #expect(outputs.matching("MacBook")?.id == 1)
    #expect(outputs.matching("lorcan")?.id == 2)
}

@Test func theOnlyNameThatContainsItMatches() {
    #expect(outputs.matching("AirPods")?.id == 2)
    #expect(outputs.matching("display")?.id == 3)
}

@Test func caseAndAccentsAreIgnored() {
    #expect(outputs.matching("CAFE")?.id == 4)
    #expect(outputs.matching("café")?.id == 4)
}

@Test func severalMatchesOrNoneMatchNothing() {
    #expect(outputs.matching("Speakers") == nil)
    #expect(outputs.matching("Headphones") == nil)
    #expect(outputs.matching("") == nil)
    #expect(outputs.matching("   ") == nil)
    #expect([AudioOutput]().matching("MacBook") == nil)
}
