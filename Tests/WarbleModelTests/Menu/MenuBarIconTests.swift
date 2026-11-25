import Foundation
import Testing
@testable import WarbleModel

@Test func theMenuBarIconShowsUnlessItsHidden() {
    #expect(MenuBarIcon.isVisible(shown: true, updateWaiting: false))
    #expect(!MenuBarIcon.isVisible(shown: false, updateWaiting: false))
}

@Test func aHiddenMenuBarIconComesBackWhileAnUpdateWaits() {
    #expect(MenuBarIcon.isVisible(shown: false, updateWaiting: true))
    #expect(MenuBarIcon.isVisible(shown: true, updateWaiting: true))
}
