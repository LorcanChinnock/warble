import os
import SwiftUI
import WarbleCore

/// Warble's own long-lived objects, built once by `AppDelegate` and passed to whatever needs them, so nothing reaches
/// for a shared instance. Views get them through the SwiftUI environment (`inject(_:)`).
@MainActor
final class AppEnvironment {
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
    let notchSettings: NotchSettings
    let hotkeys: HotkeyCenter
    let settingsWindow: SettingsWindow

    init() {
        updater = Updater()
        displays = Displays()
        loginItem = LoginItem()
        hotkeys = HotkeyCenter()
        store = Store(state: AppState(), clock: SystemClock(), scheduler: TimerScheduler())
        let store = store
        let dispatch: (AppAction) -> Void = { [weak store] in store?.dispatch($0) }
        volume = SystemVolume()
        let outputs = CoreAudioOutputs()
        runner = EffectRunner(hotkeys: hotkeys, volume: volume, outputs: outputs)
        platform = PlatformEffects(dispatch: dispatch)
        store.perform = { [weak runner] in runner?.perform($0) }
        runner.dispatch = dispatch
        runner.platform = { [weak platform] in platform?.perform($0) }
        notchSettings = NotchSettings(dispatch: dispatch)
        notchSettings.start()
        settingsWindow = SettingsWindow()
        settingsWindow.environment = self
    }
}

extension View {
    /// Hands every view what it may read from `environment`.
    func inject(_ environment: AppEnvironment) -> some View {
        self
            .environment(environment.updater)
            .environment(environment.loginItem)
            .environment(environment.notchSettings)
    }
}
