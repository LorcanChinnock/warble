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
