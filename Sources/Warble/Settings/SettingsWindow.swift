import AppKit
import SwiftUI

/// The Settings window, made the first time it opens. Its content is dropped when it closes, so a closed window keeps
/// nothing observing the login item or updates.
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// What the window's views read. `AppEnvironment` sets it once it's built, which holds this window.
    weak var environment: AppEnvironment?
    static let size = NSSize(width: 560, height: 500)

    func show() {
        guard let environment else { return }
        let window = window ?? makeWindow()
        if window.contentView?.subviews.isEmpty ?? true {
            window.contentView = NSView(hosting: SettingsView().inject(environment))
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

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Warble Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Black and dark whatever the system appearance, like the notch.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window?.contentView = NSView()
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.window = window
        return window
    }
}
