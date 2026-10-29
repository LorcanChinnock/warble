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
    /// What the window opens at, and the least it can be made, which keeps the preview and a few rows showing.
    static let size = NSSize(width: 560, height: 780)
    static let minimumSize = NSSize(width: 520, height: 640)

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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Warble Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The website's cream in light and its dark palette in dark, following the system.
        window.backgroundColor = Warm.windowFill
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
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
