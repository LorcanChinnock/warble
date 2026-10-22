import AppKit
import SwiftUI
import WarbleCore

/// The welcome window, shown once on a first launch. Its content is dropped when it closes, and closing it saves
/// `hasSeenWelcome`, so it never opens again. It asks for no permission.
@MainActor
final class WelcomeWindow {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private let dispatch: (AppAction) -> Void
    /// What the window's views read. `AppEnvironment` sets it once it's built, which holds this window.
    weak var environment: AppEnvironment?
    static let size = NSSize(width: 460, height: 420)
    static let guide = URL(string: "https://warble.lorcanchinnock.com/docs/get-started/")!

    init(dispatch: @escaping (AppAction) -> Void) {
        self.dispatch = dispatch
    }

    func show() {
        guard let environment else { return }
        let window = window ?? makeWindow()
        if window.contentView?.subviews.isEmpty ?? true {
            window.contentView = NSView(hosting: WelcomeView(close: { [weak window] in window?.close() }).inject(environment), settings: environment.settings)
        }
        // Warble has no Dock icon, so it takes one while the window is open, to show in ⌘Tab.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to Warble")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closed() }
        }
        self.window = window
        return window
    }

    private func closed() {
        UserDefaults.standard.set(true, forKey: PreferenceKey.hasSeenWelcome)
        window?.contentView = NSView()
        // Settings may still be open and wants the Dock icon.
        if !(NSApp.windows.contains { $0.isVisible && $0.title == String(localized: "Warble Settings") }) {
            NSApp.setActivationPolicy(.accessory)
        }
        dispatch(.welcomeClosed)
    }
}

/// One screen: what Warble is, the two choices a listener might want right away, and where the guide is.
private struct WelcomeView: View {
    let close: () -> Void
    @Setting(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon: Bool
    @Environment(LoginItem.self) private var loginItem

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Welcome to Warble")
                    .font(.title.weight(.semibold))
                Text("Play something and it shows in your notch. Hover over the notch to open the player.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Form {
                Section {
                    Toggle(isOn: Binding { loginItem.isEnabled } set: { loginItem.set($0) }) {
                        Text("Open at login")
                        Text("Warble opens when you log in, so the notch is there after a restart.")
                    }
                    .accessibilityLabel(Text("Open at login"))
                    .accessibilityHint(Text("Warble opens when you log in, so the notch is there after a restart."))
                    Toggle(isOn: $showMenuBarIcon) {
                        Text("Show icon in the menu bar")
                        Text("Open Warble again from Applications to bring it back.")
                    }
                    .accessibilityLabel(Text("Show icon in the menu bar"))
                    .accessibilityHint(Text("Open Warble again from Applications to bring it back."))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Link("Read the guide", destination: WelcomeWindow.guide)
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: WelcomeWindow.size.width, height: WelcomeWindow.size.height)
        .onAppear { loginItem.refresh() }
    }
}
