import AppKit
import SwiftUI
import WarbleCore

/// Records one action's shortcut at a time in Settings › Shortcuts. It watches keys and clicks only while recording,
/// and only in Warble's own windows, and pauses Warble's shortcuts meanwhile so pressing one records it.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var recording: WarbleAction?
    /// Why the last key pressed for an action didn't become its shortcut.
    private(set) var refusal: (action: WarbleAction, message: String)?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private let hotkeys: HotkeyCenter
    @ObservationIgnored private let settings: SettingsStore

    init(hotkeys: HotkeyCenter, settings: SettingsStore) {
        self.hotkeys = hotkeys
        self.settings = settings
    }

    func start(_ action: WarbleAction) {
        stop()
        refusal = nil
        recording = action
        hotkeys.suspend()
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.press(event) }
            return nil
        } as Any)
        // A click anywhere ends recording, and a click on a recorder starts it again there.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.stop() }
            return event
        } as Any)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        if recording != nil {
            recording = nil
            hotkeys.resume()
        }
    }

    /// Stops recording and forgets any refusal, for a page that's gone, so it opens again as new.
    func reset() {
        stop()
        refusal = nil
    }

    /// Written before recording stops, so the shortcuts register once, without the cleared one.
    func clear(_ action: WarbleAction) {
        refusal = nil
        settings.set("", forKey: PreferenceKey.hotkey(action))
        stop()
    }

    private func press(_ event: NSEvent) {
        guard let action = recording else {
            return
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), eventFlags: CGEventFlags(rawValue: UInt64(flags.rawValue)))
        let preferences = Preferences()
        let bindings = WarbleAction.allCases.reduce(into: [WarbleAction: KeyCombo]()) { $0[$1] = preferences.hotkey(for: $1) }
        switch ShortcutRecording(combo, for: action, bindings: bindings) {
        case .cancel:
            refusal = nil
            stop()
        case .clear:
            clear(action)
        case .needsModifier:
            // Recording goes on, so the next key can be the right one.
            NSSound.beep()
            refusal = (action, String(localized: "Add ⌘, ⌥ or ⌃, so the shortcut doesn't catch your typing."))
        case .refused(let conflict):
            NSSound.beep()
            refusal = (action, conflict.message(for: combo))
        case .record(let combo):
            refusal = nil
            settings.set(combo.encoded, forKey: PreferenceKey.hotkey(action))
            stop()
        }
    }
}

/// One action's row: its name, the recorder and a button that clears the shortcut.
struct ShortcutRow: View {
    let action: WarbleAction
    let recorder: ShortcutRecorder
    @Setting private var encoded: String
    @Environment(HotkeyCenter.self) private var hotkeys

    init(action: WarbleAction, recorder: ShortcutRecorder) {
        self.action = action
        self.recorder = recorder
        _encoded = Setting(PreferenceKey.hotkey(action))
    }

    private var combo: KeyCombo? { KeyCombo(encoded: encoded) }
    private var isRecording: Bool { recorder.recording == action }

    private var shortcut: String {
        if isRecording {
            String(localized: "Press Keys…")
        } else {
            combo?.displayString ?? String(localized: "Record Shortcut")
        }
    }

    /// What's wrong, or what to press while recording.
    private var note: String? {
        if let refusal = recorder.refusal, refusal.action == action {
            refusal.message
        } else if isRecording {
            String(localized: "Press the keys to use, or Esc to cancel.")
        } else if combo != nil, hotkeys.unavailable.contains(action) {
            String(localized: "Another app uses this shortcut. Try another.")
        } else {
            nil
        }
    }

    var body: some View {
        SettingsRow(title: Text(action.title), detail: note.map { Text($0) }) {
            HStack(spacing: 6) {
                Button {
                    recorder.start(action)
                } label: {
                    Text(shortcut)
                        .frame(minWidth: 130)
                }
                .buttonStyle(.warble)
                .accessibilityLabel(Text("\(action.title) shortcut"))
                .accessibilityValue(Text(isRecording ? shortcut : combo?.displayString ?? String(localized: "None")))
                Button {
                    recorder.clear(action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Native.secondary)
                }
                .buttonStyle(.notch)
                .help(Text("Clear Shortcut"))
                .accessibilityLabel(Text("Clear \(action.title) shortcut"))
                // Kept in place while hidden, so every recorder lines up.
                .opacity(combo == nil ? 0 : 1)
                .disabled(combo == nil)
                .accessibilityHidden(combo == nil)
            }
        }
    }
}
