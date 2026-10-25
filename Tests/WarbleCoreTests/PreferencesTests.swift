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
    #expect(Preferences.hasSavedSettings([PreferenceKey.hotkey(.playPause)]))
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

@Test func shortcutsStartClearedAndResetClearsACustomOne() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    let prefs = Preferences(store: suite.store)
    #expect(WarbleAction.allCases.allSatisfy { prefs.hotkey(for: $0) == nil })
    let custom = KeyCombo(keyCode: 49, modifiers: KeyCombo.control | KeyCombo.option)
    suite.store.set(custom.encoded, forKey: PreferenceKey.hotkey(.playPause))
    #expect(prefs.hotkey(for: .playPause) == custom)
    Preferences.resetAll(in: suite.store)
    #expect(prefs.hotkey(for: .playPause) == nil)
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

@Test func hoveringTheIdleNotchShowsTheLastTrackByDefault() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    #expect(Preferences(store: suite.store).idleHover == .lastPlayed)
    suite.store.set(IdleHover.nothing.rawValue, forKey: PreferenceKey.idleHover)
    #expect(Preferences(store: suite.store).idleHover == .nothing)
    suite.store.set("sometimes", forKey: PreferenceKey.idleHover)
    #expect(Preferences(store: suite.store).idleHover == .lastPlayed)
}

@Test func onlyAnEmptyDomainIsAFirstLaunch() {
    #expect(Preferences.isFirstLaunch(saved: [:]))
    #expect(Preferences.isFirstLaunch(saved: ["SUHasLaunchedBefore": true]))
    #expect(!Preferences.isFirstLaunch(saved: [PreferenceKey.showMenuBarIcon: true]))
    #expect(!Preferences.isFirstLaunch(saved: [PreferenceKey.hasSeenWelcome: true]))
    #expect(Preferences.isFirstLaunch(saved: [PreferenceKey.hasSeenWelcome: false]))
}

@Test func activitiesStartOffWithNoAppsListedOrBlocked() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    let preferences = Preferences(store: suite.store)
    #expect(!preferences.activities)
    #expect(preferences.activityApps.isEmpty)
    #expect(preferences.activityBlocked.isEmpty)
}

@Test func theActivityAppsAndTheBlockedOnesAreReadBack() throws {
    let suite = try TestDefaults()
    defer { suite.remove() }
    Preferences.registerDefaults(in: suite.store)
    suite.store.set(["TEAM.dev.lorcan.Shot": "Shot", "script|/usr/bin/python3|Timer": "Timer"], forKey: PreferenceKey.activityApps)
    suite.store.set(["TEAM.dev.lorcan.Shot", "TEAM.dev.lorcan.Shot"], forKey: PreferenceKey.activityBlocked)
    let preferences = Preferences(store: suite.store)
    #expect(preferences.activityApps["TEAM.dev.lorcan.Shot"] == "Shot")
    #expect(preferences.activityBlocked == ["TEAM.dev.lorcan.Shot"])
    Preferences.resetAll(in: suite.store)
    #expect(Preferences(store: suite.store).activityBlocked.isEmpty)
}
