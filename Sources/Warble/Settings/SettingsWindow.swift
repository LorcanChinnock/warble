import AppKit
import SwiftUI

/// Settings' tabs, in the toolbar's order.
enum SettingsTab: Int, CaseIterable {
    case notch, general, about
}

/// The Settings window: a standard preferences window with Notch, General and About as toolbar tabs, each a grouped form
/// that the window fits, resizing as the tab changes. It's made the first time it opens, and its tabs are dropped when it
/// closes, so a closed window keeps nothing observing the login item or updates.
@MainActor
final class SettingsWindow {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// The tab it last showed, which it opens on again.
    private var lastTab = SettingsTab.notch
    /// What the window's views read. `AppEnvironment` sets it once it's built, which holds this window.
    weak var environment: AppEnvironment?
    static let width: CGFloat = 600

    /// Opens Settings, on `tab` if given, or else on the tab it last showed.
    func show(_ tab: SettingsTab? = nil) {
        guard let environment else { return }
        let window = window ?? makeWindow()
        let isNew = window.contentViewController == nil
        if isNew {
            window.contentViewController = makeTabs(environment)
        }
        if let tabs = window.contentViewController as? NSTabViewController, isNew || tab != nil {
            tabs.selectedTabViewItemIndex = (tab ?? lastTab).rawValue
        }
        if isNew {
            window.center()
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
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { return }
                if let tabs = window.contentViewController as? NSTabViewController {
                    self.lastTab = SettingsTab(rawValue: tabs.selectedTabViewItemIndex) ?? .notch
                }
                window.contentViewController = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
        self.window = window
        return window
    }

    private func makeTabs(_ environment: AppEnvironment) -> NSTabViewController {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for tab in SettingsTab.allCases {
            let item = NSTabViewItem(viewController: SettingsTabController(tab.content.inject(environment)))
            item.label = tab.label
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }
        return tabs
    }
}

private extension SettingsTab {
    var label: String {
        switch self {
        case .notch: String(localized: "Notch", comment: "A Settings tab: what the notch shows and how it looks.")
        case .general: String(localized: "General", comment: "A Settings tab: opening at login, and help.")
        case .about: String(localized: "About", comment: "A Settings tab: the version, updates and acknowledgements.")
        }
    }

    /// The board draws a screen with a notch; `macbook` is the nearest system symbol.
    var symbol: String {
        switch self {
        case .notch: "macbook"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }

    @MainActor var content: AnyView {
        switch self {
        case .notch: AnyView(NotchTab())
        case .general: AnyView(GeneralTab())
        case .about: AnyView(AboutTab())
        }
    }
}

/// The toolbar tabs, which put the selected tab's name in the title bar, as standard preferences windows do.
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? ""
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = tabView.selectedTabViewItem?.label ?? ""
    }
}

/// One tab, hosting its SwiftUI form at the window's width and asking for the form's own height, which the tab
/// controller resizes the window to.
private final class SettingsTabController: NSViewController {
    private let content: AnyView

    init(_ content: some View) {
        self.content = AnyView(content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let measured = content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { [weak self] height in
                // After SwiftUI's layout pass, never inside it: resizing the window from there throws.
                DispatchQueue.main.async { self?.fit(height) }
            }
            .frame(width: SettingsWindow.width)
            .frame(maxHeight: .infinity, alignment: .top)
        view = NSView(hosting: measured)
        // Measured once before the window shows, so it opens at the tab's height rather than growing into it.
        let height = NSView.fittingHeight(of: content.fixedSize(horizontal: false, vertical: true), width: SettingsWindow.width)
        view.frame.size = NSSize(width: SettingsWindow.width, height: height)
        preferredContentSize = view.frame.size
    }

    private func fit(_ height: CGFloat) {
        guard height > 0, height != preferredContentSize.height else { return }
        preferredContentSize = NSSize(width: SettingsWindow.width, height: height)
    }
}
