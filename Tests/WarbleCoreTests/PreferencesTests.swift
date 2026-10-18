import Foundation
import Testing
@testable import WarbleCore

@Test func theMenuBarIconShowsByDefault() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    #expect(Preferences(store: suite.store).showMenuBarIcon)
}

@Test func resettingRestoresTheDefaults() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    suite.store.set(false, forKey: PreferenceKey.showMenuBarIcon)
    #expect(!Preferences(store: suite.store).showMenuBarIcon)
    Preferences.resetAll(in: suite.store)
    #expect(Preferences(store: suite.store).showMenuBarIcon)
}

@Test func onlyWarblesOwnKeysCountAsSavedSettings() {
    #expect(Preferences.hasSavedSettings([PreferenceKey.showMenuBarIcon]))
    #expect(!Preferences.hasSavedSettings(["NSWindow Frame Settings", "SUHasLaunchedBefore"]))
}
