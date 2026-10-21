import AppKit
import SwiftUI

/// The Settings window, made the first time it opens. Its content is dropped when it closes, so a closed window keeps
/// nothing observing settings or displays.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?
    static let size = NSSize(width: 720, height: 520)

    static func show(section: SettingsSection? = nil) {
        if let section {
            SettingsNavigation.shared.section = section
        }
        let window = window ?? makeWindow()
        if window.contentView?.subviews.isEmpty ?? true {
            window.contentView = NSView(hosting: SettingsView())
        }
        // Warble has no Dock icon, so it takes one while Settings is open, to show in ⌘Tab and get the app menu.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is cooperative, so it can be refused right after the policy changes; raise the window anyway and
        // ask again once the policy has settled.
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    /// Whether the window is open on `section`.
    static func isShowing(_ section: SettingsSection) -> Bool {
        window?.isVisible == true && SettingsNavigation.shared.section == section
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Warble Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                SettingsWindow.window?.contentView = NSView()
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.window = window
        return window
    }
}
