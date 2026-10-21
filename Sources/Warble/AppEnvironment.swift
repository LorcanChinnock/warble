import SwiftUI
import WarbleCore

/// Warble's own long-lived objects, built once by `AppDelegate` and passed to whatever needs them, so nothing reaches
/// for a shared instance. Views get them through the SwiftUI environment (`inject(_:)`).
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let updater: Updater
    let displays: Displays
    let loginItem: LoginItem
    let hotkeys: HotkeyCenter
    let navigation: SettingsNavigation
    let settingsWindow: SettingsWindow
    let toast: Toast
    let recorder: ShortcutRecorder

    init() {
        // Before anything reads a setting, so every read falls back to the registered default.
        Preferences.registerDefaults()
        settings = SettingsStore()
        updater = Updater()
        displays = Displays()
        loginItem = LoginItem()
        hotkeys = HotkeyCenter()
        navigation = SettingsNavigation()
        settingsWindow = SettingsWindow(navigation: navigation)
        toast = Toast(hotkeys: hotkeys, settings: settings)
        recorder = ShortcutRecorder(hotkeys: hotkeys, settings: settings)
        settingsWindow.environment = self
        let settingsWindow = settingsWindow
        let toast = toast
        hotkeys.onUnavailable = { failed in
            // Settings › Shortcuts says so under the shortcut, so the toast is for when it isn't showing.
            guard !settingsWindow.isShowing(.shortcuts) else { return }
            // Usually another app owns the shortcut, or two Warble actions share it.
            toast.error("Shortcut unavailable: \(failed.sorted().joined(separator: ", ")). Another app may use it, so choose a different one in Settings › Shortcuts.")
        }
    }
}

extension View {
    /// Hands every view what it may read from `environment`.
    func inject(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment.settings)
            .environment(environment.updater)
            .environment(environment.displays)
            .environment(environment.loginItem)
            .environment(environment.hotkeys)
            .environment(environment.navigation)
            .environment(environment.recorder)
    }
}
