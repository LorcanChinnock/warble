import AppKit
import os
import WarbleCore

private let log = Logger.warble("app")

/// Carries out the effects that need AppKit or a Mac-only framework, and sends what they find back to the store.
@MainActor
final class PlatformEffects {
    private let dispatch: (AppAction) -> Void
    /// Opens or closes the notch with the keyboard. The notch sets it, since it knows which notch the pointer is on.
    private var clickMonitor: Any?

    init(dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
    }

    func perform(_ effect: AppEffect) {
        switch effect {
        case .watchClicksOutside(let watch):
            watchClicksOutside(watch)
        case .openApp(let bundleIdentifier, let title):
            Task { await Self.openApp(bundleIdentifier: bundleIdentifier, title: title) }
        case .openArtist(let bundleIdentifier, let title):
            Task {
                guard let page = await ArtistPage.find(bundleIdentifier: bundleIdentifier, title: title) else {
                    return await Self.openApp(bundleIdentifier: bundleIdentifier, title: title)
                }
                if let app = page.app.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:)) {
                    _ = try? await NSWorkspace.shared.open([page.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } else {
                    NSWorkspace.shared.open(page.url)
                }
            }
        case .haptic:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        default:
            break
        }
    }

    /// In a browser, the tab that's playing; otherwise, or if that fails, the app, opened if it's quit.
    private static func openApp(bundleIdentifier: String, title: String) async {
        if await BrowserTabs.focus(bundleIdentifier: bundleIdentifier, title: title) { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Clicks in other apps close the open notches; a click on the panel itself is the panel's own.
    private func watchClicksOutside(_ watch: Bool) {
        if watch, clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.dispatch(.dismiss(except: nil)) }
            }
        } else if !watch, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}
