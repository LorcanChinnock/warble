import AppKit
import Carbon.HIToolbox
import os
import WarbleCore

private let log = Logger.warble("hotkeys")

@MainActor
@Observable
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    @ObservationIgnored var onPress: ((WarbleAction) -> Void)?
    /// The actions whose shortcut macOS refused, usually because another app has it. Settings says so under each.
    private(set) var unavailable: Set<WarbleAction> = []
    @ObservationIgnored private var refs: [EventHotKeyRef] = []
    @ObservationIgnored private var handlerInstalled = false
    @ObservationIgnored private var registered: [WarbleAction: KeyCombo] = [:]
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// True while the shortcut recorder listens, so global hotkeys don't swallow the keystroke.
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var temporaryRef: EventHotKeyRef?
    @ObservationIgnored private var onTemporaryPress: (() -> Void)?
    private static let temporaryID = UInt32.max

    /// Registers the shortcuts in Settings, and again whenever one changes, so a change works without a relaunch.
    func start() {
        reloadFromPreferences()
        guard defaultsObserver == nil else {
            return
        }
        // Any write to Warble's defaults; reloading registers again only when a shortcut changed.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { _ in
            MainActor.assumeIsolated {
                HotkeyCenter.shared.reloadFromPreferences()
            }
        }
    }

    func reloadFromPreferences(force: Bool = false) {
        guard !isSuspended else {
            return
        }
        let prefs = Preferences()
        let bindings = WarbleAction.allCases.reduce(into: [WarbleAction: KeyCombo]()) { $0[$1] = prefs.hotkey(for: $1) }
        if force || bindings != registered {
            register(bindings)
        }
    }

    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        isSuspended = false
        reloadFromPreferences(force: true)
    }

    /// Takes `combo` from every app until `unregisterTemporary()`, for a key that only means something briefly,
    /// such as ⌘Z while a toast offers Undo. Replaces any earlier temporary key. False when it couldn't be registered.
    @discardableResult
    func registerTemporary(_ combo: KeyCombo, onPress: @escaping () -> Void) -> Bool {
        unregisterTemporary()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5752_424C), id: Self.temporaryID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed for temporary \(combo.displayString, privacy: .public): \(status)")
            return false
        }
        temporaryRef = ref
        onTemporaryPress = onPress
        return true
    }

    func unregisterTemporary() {
        if let temporaryRef {
            UnregisterEventHotKey(temporaryRef)
        }
        temporaryRef = nil
        onTemporaryPress = nil
    }

    private func register(_ bindings: [WarbleAction: KeyCombo]) {
        unregisterAll()
        installHandlerIfNeeded()
        registered = bindings
        var failed: [String] = []
        var unavailable: Set<WarbleAction> = []
        for (action, combo) in bindings {
            guard let index = WarbleAction.allCases.firstIndex(of: action) else {
                continue
            }
            let id = EventHotKeyID(signature: OSType(0x5752_424C), id: UInt32(index))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                log.error("RegisterEventHotKey failed for \(action.rawValue, privacy: .public): \(status)")
                failed.append(combo.displayString)
                unavailable.insert(action)
            }
        }
        if self.unavailable != unavailable {
            self.unavailable = unavailable
        }
        // Settings › Shortcuts says so under the shortcut, so the toast is for when it isn't showing.
        if !failed.isEmpty, !SettingsWindow.isShowing(.shortcuts) {
            // Usually another app owns the shortcut, or two Warble actions share it.
            Toast.error("Shortcut unavailable: \(failed.sorted().joined(separator: ", ")). Another app may use it, so choose a different one in Settings › Shortcuts.")
        }
        log.notice("Registered \(self.refs.count) hotkeys")
    }

    private func unregisterAll() {
        for ref in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        registered = [:]
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
            let index = Int(id.id)
            // Carbon dispatches hotkey events on the main thread.
            MainActor.assumeIsolated {
                if id.id == HotkeyCenter.temporaryID {
                    HotkeyCenter.shared.onTemporaryPress?()
                } else if WarbleAction.allCases.indices.contains(index) {
                    HotkeyCenter.shared.onPress?(WarbleAction.allCases[index])
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
