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
    /// The checks behind the "!", as the notch's cards draw them.
    let doctor: DoctorModel
    /// The output's volume, which a scroll or a key reads before it changes it.
    let volume: SystemVolume
    let updater: Updater
    let displays: Displays
    let loginItem: LoginItem
    let hotkeys: HotkeyCenter
    let navigation: SettingsNavigation
    let settingsWindow: SettingsWindow
    let welcomeWindow: WelcomeWindow
    let toast: Toast
    let recorder: ShortcutRecorder

    /// `lastPlayed` is where the last track played is kept, which the preview keeps only in memory..
    init(lastPlayed: any LastPlayedStore) {
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
                stayVisibleAfterPausing: preferences.stayVisibleAfterPausing, idleHover: preferences.idleHover,
                showsTrackToast: preferences.trackChangeToast, toastsInFullScreen: preferences.toastsInFullScreen,
                swipeToSkip: preferences.swipeToSkip, podcastSkips: preferences.podcastSkips, dragArtOut: preferences.dragArtOut,
                showsVirtualTitle: preferences.virtualTitle,
                checks: Doctor.checks(Doctor.Facts(adapter: .working, macOS: .running))
            ),
            clock: SystemClock(), scheduler: TimerScheduler()
        )
        let store = store
        let dispatch: (AppAction) -> Void = { [weak store] in store?.dispatch($0) }
        doctor = DoctorModel(updater: updater, dispatch: dispatch)
        volume = SystemVolume()
        let outputs = CoreAudioOutputs()
        runner = EffectRunner(hotkeys: hotkeys, volume: volume, outputs: outputs, lastPlayed: lastPlayed, remember: LastPlayedFile.remembering)
        platform = PlatformEffects(dispatch: dispatch)
        store.perform = { [weak runner] in runner?.perform($0) }
        runner.dispatch = dispatch
        runner.platform = { [weak platform] in platform?.perform($0) }
        runner.tabLink = { bundleIdentifier, title in
            // Only with the setting on, so macOS never asks about a browser until the user has asked for this.
            guard Preferences().resumeBrowserTabs else { return nil }
            return await ScriptSource.tabLink(in: bundleIdentifier, title: title)
        }
        runner.appName = { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName }
        runner.logError = { message in Logger.warble("notch").error("\(message, privacy: .public)") }
        navigation = SettingsNavigation()
        settingsWindow = SettingsWindow(navigation: navigation)
        toast = Toast(hotkeys: hotkeys, settings: settings)
        recorder = ShortcutRecorder(hotkeys: hotkeys, settings: settings)
        welcomeWindow = WelcomeWindow(dispatch: dispatch)
        settingsWindow.environment = self
        welcomeWindow.environment = self
        let settingsWindow = settingsWindow
        let welcomeWindow = welcomeWindow
        platform.showWelcome = { [weak welcomeWindow] in welcomeWindow?.show() }
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
