import SwiftUI
import WarbleCore
import WarbleModel

@main
struct WarbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let environment = appDelegate.environment
        MenuBarExtra {
            WarbleMenu(updater: environment.updater, settingsWindow: environment.settingsWindow)
                .inject(environment)
        } label: {
            // Reads only `pendingVersion`, so a download's progress doesn't redraw the icon.
            let waiting = environment.updater.pendingVersion != nil
            Image(nsImage: waiting ? .menuBarIconWithDot : .menuBarIcon)
                .accessibilityLabel(Text(verbatim: AppMenuLabel.icon(updateWaiting: waiting)))
        }
    }
}

/// The menu bar menu, in the order `AppMenu` gives. The notch's right-click menu, `NotchMenu`, has the same items.
private struct WarbleMenu: View {
    let updater: Updater
    let settingsWindow: SettingsWindow

    var body: some View {
        ForEach(Array(AppMenu.items(update: updater.menuItem).enumerated()), id: \.offset) { _, item in
            switch item {
            case .about:
                Button("About Warble") { settingsWindow.show(.about) }
            case .update(let update):
                Button { updater.checkForUpdates() } label: {
                    if update.hasDot {
                        Text(verbatim: update.title + " ") + Text(Image(nsImage: .updateDot))
                    } else {
                        Text(verbatim: update.title)
                    }
                }
                .disabled(!update.isEnabled)
            case .settings:
                Button("Settings…") { settingsWindow.show() }
                    .keyboardShortcut(",")
            case .quit:
                Button("Quit Warble") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            case .separator:
                Divider()
            case .openApp, .copySong:
                EmptyView()
            }
        }
    }
}
