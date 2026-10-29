import Testing
@testable import WarbleModel

@Test func aRightClickOpensTheMenu() {
    #expect(NotchClick.opensMenu(isRightButtonDown: true, isLeftButtonDown: false, control: false))
}

@Test func aControlClickOpensTheMenu() {
    #expect(NotchClick.opensMenu(isRightButtonDown: false, isLeftButtonDown: true, control: true))
}

@Test func anOrdinaryClickDoesNot() {
    #expect(!NotchClick.opensMenu(isRightButtonDown: false, isLeftButtonDown: true, control: false))
}

@Test func controlAloneDoesNot() {
    #expect(!NotchClick.opensMenu(isRightButtonDown: false, isLeftButtonDown: false, control: true))
}
