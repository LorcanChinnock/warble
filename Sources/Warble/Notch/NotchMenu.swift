import AppKit

/// What a right-click on any notch offers: the app it follows, Settings, updates and Quit, so Warble can be reached and
/// quit with its menu bar icon off. Built only when it opens, so a resting notch keeps nothing up to date.
@MainActor
enum NotchMenu {
    /// `source` is the bundle identifier of the app that's playing, or while Idle the one that played last.
    static func make(source: String?, updater: Updater, openApp: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        if let source, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) {
            let item = ActionItem(title: String(localized: "Open \(name(of: app, bundleIdentifier: source))"), action: openApp)
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
            menu.addItem(.separator())
        }
        menu.addItem(ActionItem(title: String(localized: "Settings…"), keyEquivalent: ",") { SettingsWindow.show() })
        if let version = updater.pendingVersion {
            menu.addItem(ActionItem(title: String(localized: "Update to \(version)…")) { updater.checkForUpdates() })
        } else {
            let item = ActionItem(title: String(localized: "Check for Updates…")) { updater.checkForUpdates() }
            item.isEnabled = updater.canCheckForUpdates
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: String(localized: "Quit Warble"), keyEquivalent: "q") { NSApp.terminate(nil) })
        // Items keep the enabled state given above rather than asking their targets.
        menu.autoenablesItems = false
        return menu
    }

    /// The running app's name, or else the one Finder shows.
    private static func name(of app: URL, bundleIdentifier: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.localizedName {
            return running
        }
        let name = FileManager.default.displayName(atPath: app.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, keyEquivalent: String = "", action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(runAction), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func runAction() {
        run()
    }
}
