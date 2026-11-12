import AppKit
import WarbleCore
import WarbleModel

/// What a right-click on any notch offers: the app it follows and copying the song, then the menu bar menu's items in
/// the same order (`AppMenu`), so Warble can be reached from the notch as well as the menu bar. Built only when it
/// opens, so a resting notch keeps nothing up to date. The menu bar menu (`StatusItem`) is filled by the same code.
@MainActor
enum NotchMenu {
    /// `source` is the bundle identifier of the app that's playing, or while Idle the one that played last. `copyText`
    /// is the song and artist to copy, from `TrackTitle.copyText`, or `nil` while no track with a title shows.
    static func make(
        source: String?, copyText: String?, updater: Updater, settingsWindow: SettingsWindow, openApp: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        fill(menu, source: source, copyText: copyText, updater: updater, settingsWindow: settingsWindow, openApp: openApp)
        return menu
    }

    /// Adds the items to `menu`: the app and Copy Song and Artist when `source` and `copyText` are given, as on the
    /// notch, and then the menu bar menu's items.
    static func fill(
        _ menu: NSMenu, source: String?, copyText: String?, updater: Updater, settingsWindow: SettingsWindow, openApp: @escaping () -> Void
    ) {
        let app = source.flatMap { source in NSWorkspace.shared.urlForApplication(withBundleIdentifier: source).map { (source, $0) } }
        for item in AppMenu.items(update: updater.menuItem, openApp: app != nil, copySong: copyText != nil) {
            switch item {
            case .openApp:
                guard let (source, url) = app else {
                    continue
                }
                let open = ActionItem(title: String(localized: "Open \(name(of: url, bundleIdentifier: source))"), action: openApp)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                open.image = icon
                menu.addItem(open)
            case .copySong:
                guard let copyText else {
                    continue
                }
                menu.addItem(ActionItem(title: String(localized: "Copy Song and Artist")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyText, forType: .string)
                })
            case .about:
                menu.addItem(ActionItem(title: String(localized: "About Warble")) { settingsWindow.show(.about) })
            case .update(let update):
                let check = ActionItem(title: update.title) { updater.checkForUpdates() }
                if update.hasDot {
                    check.attributedTitle = titleWithDot(update.title)
                    // The dot is a text attachment, so the item's name would otherwise end in U+FFFC, which VoiceOver
                    // reads out.
                    check.setAccessibilityTitle(update.title)
                }
                check.isEnabled = update.isEnabled
                menu.addItem(check)
            case .settings:
                menu.addItem(ActionItem(title: String(localized: "Settings…"), keyEquivalent: ",") { settingsWindow.show() })
            case .quit:
                menu.addItem(ActionItem(title: String(localized: "Quit Warble"), keyEquivalent: "q") { NSApp.terminate(nil) })
            case .separator:
                menu.addItem(.separator())
            }
        }
        // Items keep the enabled state given above rather than asking their targets.
        menu.autoenablesItems = false
    }

    /// The title followed by the accent dot, as the menu bar menu shows a waiting update.
    private static func titleWithDot(_ title: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title + " ", attributes: [.font: font])
        let dot = NSTextAttachment()
        dot.image = .updateDot
        // Centred on the text's x-height, as the menu bar menu's dot sits.
        let size = NSImage.updateDot.size
        dot.bounds = CGRect(x: 0, y: (font.xHeight - size.height) / 2, width: size.width, height: size.height)
        text.append(NSAttributedString(attachment: dot))
        return text
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
