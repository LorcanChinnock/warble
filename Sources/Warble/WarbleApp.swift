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
        Divider()
        Button("Quit Warble") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// A rule for each display without a camera housing, until the Settings window has a place for them.
private struct DisplaysMenu: View {
    @Setting(PreferenceKey.virtualNotch) private var rules: [String: String]
    private let displays = Displays.shared

    var body: some View {
        let virtual = displays.all.filter { $0.notch == nil }
        if !virtual.isEmpty {
            Menu("Notch on Displays") {
                ForEach(virtual, id: \.id) { display in
                    Picker(displays.names[display.id] ?? display.id, selection: rule(display)) {
                        Text("Off").tag(VirtualNotchRule.off)
                        Text("Always").tag(VirtualNotchRule.always)
                        Text("When There's No Notch").tag(VirtualNotchRule.noNotch)
                    }
                }
            }
            Divider()
        }
    }

    private func rule(_ display: NotchDisplay) -> Binding<VirtualNotchRule> {
        Binding {
            rules[display.id].flatMap(VirtualNotchRule.init(rawValue:)) ?? .default(isMain: display.isMain)
        } set: {
            rules[display.id] = $0.rawValue
        }
    }
}

/// The displays connected now, kept up to date for the menu.
@MainActor
@Observable
private final class Displays {
    static let shared = Displays()

    private(set) var all: [NotchDisplay] = []
    private(set) var names: [String: String] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        read()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        all = NSScreen.notchDisplays
        names = Dictionary(NSScreen.screens.map { ($0.uuid, $0.localizedName) }, uniquingKeysWith: { first, _ in first })
    }
}
