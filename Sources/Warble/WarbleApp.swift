import SwiftUI
import WarbleCore

@main
struct WarbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Setting(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon: Bool

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            WarbleMenu(updater: Updater.shared)
        } label: {
            Image(systemName: Updater.shared.pendingVersion == nil ? "music.note" : "arrow.down.circle")
        }
    }
}

private struct WarbleMenu: View {
    let updater: Updater

    var body: some View {
        if let version = updater.pendingVersion {
            Button("Update to \(version)…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        Divider()
        Button("Quit Warble") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
