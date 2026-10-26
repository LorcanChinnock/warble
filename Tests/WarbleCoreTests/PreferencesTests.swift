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
    #expect(Preferences.hasSavedSettings(["hotkey.play-pause"]))
    #expect(!Preferences.hasSavedSettings(["NSWindow Frame Settings", "SUHasLaunchedBefore"]))
}

@Test func textIsStandardSizeByDefault() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    #expect(Preferences(store: suite.store).textSize == .standard)
    suite.store.set("huge", forKey: PreferenceKey.textSize)
    #expect(Preferences(store: suite.store).textSize == .standard)
}

/// `@Setting(key)` with no default of its own takes the one `Preferences` registers, so every key a view declares that way
/// must have one. Reads the app's sources, since the views can't be built here; a `PreferenceKey` is named as its value.
@Test func everySettingKeyHasARegisteredDefault() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = root.appendingPathComponent("Sources/Warble")
    let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects ?? [])
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
    var keys: Set<String> = []
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        for match in text.matches(of: /@Setting\(PreferenceKey\.(\w+)\)/) {
            keys.insert(String(match.1))
        }
    }
    #expect(keys.isSuperset(of: [PreferenceKey.showMenuBarIcon, PreferenceKey.textSize]))
    let defaults = Preferences.defaults
    for key in keys.sorted() {
        #expect(defaults[key] != nil, Comment(rawValue: key))
    }
}

@Test func everyDisplayFollowsItsDefaultUntilGivenAVirtualNotchRule() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    #expect(Preferences(store: suite.store).virtualNotchRules.isEmpty)
    suite.store.set(["studio": "always", "old": "sometimes"], forKey: PreferenceKey.virtualNotch)
    #expect(Preferences(store: suite.store).virtualNotchRules == ["studio": .always])
}

@Test func aPausedTrackStaysVisibleForTenSecondsByDefault() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    #expect(Preferences(store: suite.store).stayVisibleAfterPausing == 10)
    suite.store.set(-5, forKey: PreferenceKey.stayVisibleAfterPausing)
    #expect(Preferences(store: suite.store).stayVisibleAfterPausing == 0)
}

@Test func onlyAnEmptyDomainIsAFirstLaunch() {
    #expect(Preferences.isFirstLaunch(saved: [:]))
    #expect(Preferences.isFirstLaunch(saved: ["SUHasLaunchedBefore": true]))
    #expect(!Preferences.isFirstLaunch(saved: [PreferenceKey.showMenuBarIcon: true]))
    #expect(!Preferences.isFirstLaunch(saved: [PreferenceKey.hasSeenWelcome: true]))
    #expect(Preferences.isFirstLaunch(saved: [PreferenceKey.hasSeenWelcome: false]))
}
