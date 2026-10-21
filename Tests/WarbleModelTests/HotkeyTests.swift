import Testing
@testable import WarbleModel

@Test func hotkeyEncodeDecodeRoundTrip() {
    let custom = KeyCombo(keyCode: 122, modifiers: KeyCombo.control | KeyCombo.option)
    #expect(KeyCombo(encoded: custom.encoded) == custom)
    #expect(custom.displayString == "⌃⌥F1")
    #expect(KeyCombo(encoded: "") == nil)
    #expect(KeyCombo(encoded: "x:1") == nil)
}

@Test func noActionHasADefaultShortcut() {
    #expect(WarbleAction.allCases.allSatisfy { $0.defaultCombo == nil })
}

@Test func actionsKeepTheirPositions() {
    // HotkeyCenter numbers hotkeys by position, so a new action goes last and existing ones keep their ids.
    #expect(WarbleAction.allCases == [.playPause, .nextTrack, .previousTrack])
    #expect(WarbleAction.allCases.map(\.rawValue) == ["play-pause", "next-track", "previous-track"])
}

@Test func aShortcutTakenByAnotherActionOrMacOSConflicts() {
    let combo = KeyCombo(keyCode: 49, modifiers: KeyCombo.control | KeyCombo.option)
    let bindings: [WarbleAction: KeyCombo] = [.playPause: combo]
    #expect(WarbleAction.nextTrack.conflict(for: combo, bindings: bindings) == .taken(by: .playPause))
    // Its own shortcut, recorded again, is no conflict.
    #expect(WarbleAction.playPause.conflict(for: combo, bindings: bindings) == nil)
    #expect(WarbleAction.nextTrack.conflict(for: KeyCombo(keyCode: 12, modifiers: KeyCombo.command), bindings: bindings) == .reserved)
    #expect(WarbleAction.nextTrack.conflict(for: KeyCombo(keyCode: 49, modifiers: KeyCombo.command), bindings: [:]) == .reserved)
    // ⇧⌘Q is free: only the plain ⌘ keys are everyone's.
    #expect(WarbleAction.nextTrack.conflict(for: KeyCombo(keyCode: 12, modifiers: KeyCombo.command | KeyCombo.shift), bindings: bindings) == nil)
}

@Test func editingAndArrowKeysHaveLabels() {
    #expect(KeyCombo(keyCode: 36, modifiers: KeyCombo.command | KeyCombo.shift).displayString == "⇧⌘↩")
    for code: UInt32 in [36, 48, 53, 51, 117, 123, 124, 125, 126, 115, 119, 116, 121, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92] {
        #expect(!KeyCombo(keyCode: code, modifiers: 0).keyLabel.hasPrefix("#"))
    }
}

@Test func eachActionSendsItsCommand() {
    #expect(WarbleAction.allCases.map(\.command) == [.togglePlayPause, .nextTrack, .previousTrack])
}

@Test func recordingTakesACombo() {
    let combo = KeyCombo(keyCode: 35, modifiers: KeyCombo.option | KeyCombo.command)
    #expect(ShortcutRecording(combo, for: .playPause, bindings: [:]) == .record(combo))
    // ⇧ counts alongside another modifier.
    let shifted = KeyCombo(keyCode: 45, modifiers: KeyCombo.shift | KeyCombo.control)
    #expect(ShortcutRecording(shifted, for: .nextTrack, bindings: [:]) == .record(shifted))
}

@Test func recordingDropsBitsThatArentModifiers() {
    // Caps Lock and the Fn key's bits can ride along with an event's modifiers.
    let combo = KeyCombo(keyCode: 35, modifiers: KeyCombo.command | 1 << 10 | 1 << 17)
    #expect(ShortcutRecording(combo, for: .playPause, bindings: [:]) == .record(KeyCombo(keyCode: 35, modifiers: KeyCombo.command)))
}

@Test func escapeCancelsAndDeleteClearsARecording() {
    #expect(ShortcutRecording(KeyCombo(keyCode: 53, modifiers: 0), for: .playPause, bindings: [:]) == .cancel)
    #expect(ShortcutRecording(KeyCombo(keyCode: 51, modifiers: 0), for: .playPause, bindings: [:]) == .clear)
    #expect(ShortcutRecording(KeyCombo(keyCode: 117, modifiers: 0), for: .playPause, bindings: [:]) == .clear)
    // With a modifier they're ordinary combos.
    let delete = KeyCombo(keyCode: 51, modifiers: KeyCombo.control | KeyCombo.option)
    #expect(ShortcutRecording(delete, for: .playPause, bindings: [:]) == .record(delete))
}

@Test func aKeyWithoutAModifierOrWithOnlyShiftIsNotAShortcut() {
    #expect(ShortcutRecording(KeyCombo(keyCode: 35, modifiers: 0), for: .playPause, bindings: [:]) == .needsModifier)
    #expect(ShortcutRecording(KeyCombo(keyCode: 35, modifiers: KeyCombo.shift), for: .playPause, bindings: [:]) == .needsModifier)
    #expect(ShortcutRecording(KeyCombo(keyCode: 122, modifiers: 0), for: .playPause, bindings: [:]) == .needsModifier)
}

@Test func recordingRefusesAReservedOrTakenCombo() {
    let quit = KeyCombo(keyCode: 12, modifiers: KeyCombo.command)
    #expect(ShortcutRecording(quit, for: .playPause, bindings: [:]) == .refused(.reserved))
    let combo = KeyCombo(keyCode: 35, modifiers: KeyCombo.option | KeyCombo.command)
    #expect(ShortcutRecording(combo, for: .nextTrack, bindings: [.playPause: combo]) == .refused(.taken(by: .playPause)))
    #expect(ShortcutRecording(combo, for: .playPause, bindings: [.playPause: combo]) == .record(combo))
}
