import AppKit
import ServiceManagement
import SwiftUI
import WarbleCore
import WarbleModel

/// The first-run window, the one window Warble opens by itself at launch: what Warble does, the preview with the card
/// open, the Open at login switch and Done. It opens once, at the first launch of a new install (`FirstRun`), and never
/// for someone updating. It's built only when it opens, and `AppDelegate` drops it when it closes.
@MainActor
final class FirstRunWindow {
    static let width: CGFloat = 500
    private let window: NSWindow
    private var closeObserver: NSObjectProtocol?

    /// Whether this launch opens the window, which it records, so it never opens again. Call it before Sparkle starts.
    ///
    /// To see the window again in a dev build, launch with `-firstRunPreview YES` (`make run APP_ARGS='-firstRunPreview
    /// YES'`), which opens it for that launch without touching the stored settings. Add `-notchPreviewVirtual YES` for the
    /// text a Mac without a notch gets.
    static func opensAtLaunch() -> Bool {
        let defaults = UserDefaults.standard
        #if DEBUG
        if defaults.volatileDomain(forName: UserDefaults.argumentDomain)["firstRunPreview"] != nil {
            return true
        }
        #endif
        let stored = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:))?.keys
        guard FirstRun.opens(storedKeys: stored.map(Array.init) ?? []) else { return false }
        defaults.set(true, forKey: FirstRun.shownKey)
        return true
    }

    init(environment: AppEnvironment, onClose: @escaping @MainActor () -> Void) {
        let hasNotch = NSScreen.notchDisplays.contains { $0.notch != nil }
        let window = FirstRunPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.window = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Named for VoiceOver and the window list, though the title bar shows nothing.
        window.title = String(localized: "Welcome to Warble", comment: "The first-run window's name for VoiceOver and Mission Control; the title bar shows no title.")
        window.isReleasedWhenClosed = false
        // The close button only.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        let root = FirstRunView(hasNotch: hasNotch) { [weak window] in window?.performClose(nil) }
            .inject(environment)
        let height = NSView.fittingHeight(of: root, width: Self.width)
        // Refits when the content's height changes, as when the switch's line becomes an error, keeping the top edge.
        let measured = root
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { [weak window] height in
                // After SwiftUI's layout pass, never inside it: resizing the window from there throws.
                DispatchQueue.main.async { window?.fit(height: height) }
            }
            .frame(width: Self.width)
            .frame(maxHeight: .infinity, alignment: .top)
        window.contentView = NSView(hosting: measured)
        window.setContentSize(NSSize(width: Self.width, height: height))
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window.contentView = nil
                if let closeObserver = self.closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                }
                DockIcon.hide(for: .firstRun)
                onClose()
            }
        }
    }

    func show() {
        window.center()
        DockIcon.show(for: .firstRun)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // As in Settings: activation can be refused right after the policy changes, so raise the window anyway and ask
        // again once the policy has settled.
        window.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }
}

/// Escape closes the window, as it would a sheet, since it has no Cancel button.
private final class FirstRunPanel: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }

    /// Sets the content's height, keeping the window's top edge where it is.
    func fit(height: CGFloat) {
        let content = contentRect(forFrameRect: frame)
        guard height > 0, height != content.height else { return }
        var resized = frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - height, width: content.width, height: height))
        resized.origin.y = frame.maxY - resized.height
        setFrame(resized, display: true)
    }
}

/// The window's content, laid out as the first-run board: the preview, the title, a line on what Warble does, the Open
/// at login switch, and a footer with where Settings is and Done.
private struct FirstRunView: View {
    /// Whether any display has a notch. Without one, the text says Warble draws one.
    let hasNotch: Bool
    /// Closes the window, as Done does.
    let close: @MainActor () -> Void
    @Environment(NotchSettings.self) private var settings
    @Environment(LoginItem.self) private var loginItem

    var body: some View {
        VStack(spacing: 16) {
            NotchPreview(showsTitle: settings.showsVirtualTitle, notchFont: settings.notchFont, pauseDelay: settings.pauseDelay, cardSize: settings.cardSize, visibility: .always, showsFavourite: settings.showsFavourite, holdsOpen: true, height: 150)

            Text("Warble is in your notch")
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)

            Group {
                if hasNotch {
                    Text("Play something in any app, then point at the notch to see the song and control it. When nothing's playing, Warble stays out of sight.")
                } else {
                    Text("Play something in any app, and Warble draws a notch at the top of the screen. Point at it to see the song and control it. When nothing's playing, Warble stays out of sight.")
                }
            }
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                let login = Text("Open Warble when you log in")
                let loginDetail = loginItem.failureDetail ?? Text("So it's still there after you restart your Mac.")
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            login
                            loginDetail
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        Toggle(isOn: Binding { loginItem.isEnabled } set: { loginItem.set($0) }) {
                            login
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .accentSwitch()
                        .described(login, loginDetail)
                    }
                    if loginItem.failedChange != nil {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }

            HStack(spacing: 12) {
                Text("Settings are in the menu bar, under Warble's icon.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    close()
                } label: {
                    Text("Done")
                        .padding(.horizontal, 8)
                }
                .yellowDefaultButton()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 4)
        .padding(.bottom, 22)
        // Login Items can change in System Settings, which tells Warble nothing.
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}
