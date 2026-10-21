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
            if Updater.shared.pendingVersion == nil {
                Image(nsImage: .menuBarIcon)
                    .accessibilityLabel(Text(verbatim: "Warble"))
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
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

    var body: some View {
        DisplaysMenu()
        if let version = updater.pendingVersion {
            Button("Update to \(version)…") { updater.checkForUpdates() }
        } else {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Warble") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// A rule for each display without a camera housing, as in Settings › General, a click closer.
private struct DisplaysMenu: View {
    private let displays = Displays.shared

    var body: some View {
        let virtual = displays.all.filter { $0.notch == nil }
        if !virtual.isEmpty {
            Menu("Notch on Displays") {
                ForEach(virtual, id: \.id) { display in
                    VirtualNotchPicker(display: display, name: displays.names[display.id] ?? display.id)
                }
            }
            Divider()
        }
    }
}
