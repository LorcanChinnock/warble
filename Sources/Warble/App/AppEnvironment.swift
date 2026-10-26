import os
import SwiftUI
import WarbleCore

/// Warble's own long-lived objects, built once by `AppDelegate` and passed to whatever needs them, so nothing reaches
/// for a shared instance. Views get them through the SwiftUI environment (`inject(_:)`).
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    /// What the app has decided, which every notch draws.
    let store: Store
    /// Carries out what the store asks for, the AppKit part through `platform`.
    let runner: EffectRunner
    let platform: PlatformEffects
    /// The output's volume, which a scroll or a key reads before it changes it.
    let volume: SystemVolume
    let updater: Updater
    let displays: Displays
    let loginItem: LoginItem
    let hotkeys: HotkeyCenter
    let navigation: SettingsNavigation
    let settingsWindow: SettingsWindow

    init() {
        // Before anything reads a setting, so every read falls back to the registered default.
        Preferences.registerDefaults()
        settings = SettingsStore()
        updater = Updater()
        displays = Displays()
        loginItem = LoginItem()
        hotkeys = HotkeyCenter()
        let preferences = Preferences()
        store = Store(
            state: AppState(
                stayVisibleAfterPausing: preferences.stayVisibleAfterPausing
            ),
            clock: SystemClock(), scheduler: TimerScheduler()
        )
        let store = store
        let dispatch: (AppAction) -> Void = { [weak store] in store?.dispatch($0) }
        volume = SystemVolume()
        let outputs = CoreAudioOutputs()
        runner = EffectRunner(hotkeys: hotkeys, volume: volume, outputs: outputs)
        platform = PlatformEffects(dispatch: dispatch)
        store.perform = { [weak runner] in runner?.perform($0) }
        runner.dispatch = dispatch
        runner.platform = { [weak platform] in platform?.perform($0) }
        navigation = SettingsNavigation()
        settingsWindow = SettingsWindow(navigation: navigation)
        settingsWindow.environment = self
    }
}

extension View {
    /// Hands every view what it may read from `environment`.
    func inject(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment.settings)
            .environment(environment.updater)
            .environment(environment.loginItem)
            .environment(environment.navigation)
    }
}
