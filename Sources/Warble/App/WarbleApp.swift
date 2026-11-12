import SwiftUI

@main
struct WarbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and its menu are AppKit (`StatusItem`). A scene is still required, and this one shows
        // nothing: its Settings command, in the app menu while a window gives Warble a Dock icon, opens Warble's own
        // Settings window instead.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.environment.settingsWindow.show() }
                    .keyboardShortcut(",")
            }
        }
    }
}
