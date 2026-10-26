import SwiftUI
import WarbleCore

@main
struct WarbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let environment = appDelegate.environment
        MenuBarExtra(isInserted: showMenuBarIcon(environment.settings)) {
            WarbleMenu(updater: environment.updater, settingsWindow: environment.settingsWindow)
                .inject(environment)
        } label: {
            if environment.updater.pendingVersion == nil {
                Image(nsImage: .menuBarIcon)
                    .accessibilityLabel(Text(verbatim: "Warble"))
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
    }
}

/// Settings › General › Show menu bar icon. A scene can't read the environment `@Setting` reads, so it reads the store.
@MainActor
private func showMenuBarIcon(_ settings: SettingsStore) -> Binding<Bool> {
    Binding {
        settings.value(forKey: PreferenceKey.showMenuBarIcon) as? Bool ?? true
    } set: {
        settings.set($0, forKey: PreferenceKey.showMenuBarIcon)
    }
}

private extension NSImage {
    /// The app icon's bars as a template image, so macOS tints it for light and dark menu bars and while the menu is
    /// open. Drawn on demand, so it's sharp at every scale.
    static let menuBarIcon: NSImage = {
        let bars = IconBars.rects(height: 16)
        let image = NSImage(size: CGSize(width: bars.last!.maxX, height: 16), flipped: false) { _ in
            for bar in bars {
                NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

private struct WarbleMenu: View {
    let updater: Updater
    let settingsWindow: SettingsWindow

    var body: some View {
        if let version = updater.pendingVersion {
            Button("Update to \(version)…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        Button("Settings…") { settingsWindow.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Warble") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
