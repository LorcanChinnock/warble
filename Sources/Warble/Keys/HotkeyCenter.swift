import AppKit
import Carbon.HIToolbox
import os
import WarbleCore

private let log = Logger.warble("hotkeys")

/// Holds the keys Warble takes from every app only briefly: Escape while a notch is open and ⌘Z while a toast offers
/// Undo.
@MainActor
final class HotkeyCenter: HotkeyRegistrar {
    private var handlerInstalled = false
    /// The temporary key each owner holds, and what a press does.
    private var temporary: [TemporaryKey: (ref: EventHotKeyRef, onPress: () -> Void)] = [:]
    /// The one Carbon's handler reaches, since a C callback can't capture it.
    private static weak var current: HotkeyCenter?

    init() {
        Self.current = self
    }

    /// Takes `combo` from every app until `unregisterTemporary(for:)`, for a key that only means something briefly,
    /// such as ⌘Z while a toast offers Undo. Replaces the key `owner` held before and leaves every other owner's alone.
    /// False when it couldn't be registered.
    @discardableResult
    func registerTemporary(_ combo: KeyCombo, for owner: TemporaryKey, onPress: @escaping () -> Void) -> Bool {
        unregisterTemporary(for: owner)
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5752_424C), id: Self.temporaryID(owner))
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for temporary key \(combo.keyCode): \(status)")
            return false
        }
        temporary[owner] = (ref, onPress)
        return true
    }

    func unregisterTemporary(for owner: TemporaryKey) {
        if let held = temporary.removeValue(forKey: owner) {
            UnregisterEventHotKey(held.ref)
        }
    }

    private static func temporaryID(_ owner: TemporaryKey) -> UInt32 {
        UInt32(TemporaryKey.allCases.firstIndex(of: owner) ?? 0)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else {
            return
        }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Carbon dispatches hotkey events on the main thread.
            MainActor.assumeIsolated {
                if let owner = TemporaryKey.allCases.first(where: { HotkeyCenter.temporaryID($0) == id.id }) {
                    HotkeyCenter.current?.temporary[owner]?.onPress()
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
