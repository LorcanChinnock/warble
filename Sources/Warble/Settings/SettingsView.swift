import ServiceManagement
import SwiftUI
import WarbleCore

/// The Settings window's one page, always dark like the notch: what Warble is, whether it opens at login, and updates.
struct SettingsView: View {
    @Environment(Updater.self) private var updater
    @Environment(LoginItem.self) private var loginItem
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let guide = URL(string: "https://warble.lorcanchinnock.com/docs/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text(verbatim: "Warble")
                        .font(.title2.bold())
                    Text("Version \(Self.version)")
                        .foregroundStyle(Native.secondary)
                        .textSelection(.enabled)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .buttonStyle(.warble)
                        .disabled(!updater.canCheckForUpdates)
                        .padding(.top, 6)
                }
                // Clear of the title bar's buttons, which the content runs under.
                .padding(.top, 44)
                SettingsGroup {
                    SettingsToggleRow(
                        title: Text("Open at login"),
                        detail: loginItem.needsApproval
                            ? Text("Turned off in System Settings. Turn Warble on in Login Items to open it at login again.")
                            : nil,
                        isOn: Binding { loginItem.isEnabled } set: { loginItem.set($0) }
                    )
                    if loginItem.needsApproval {
                        SettingsRow(title: Text("Login Items")) {
                            Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                                .buttonStyle(.warble)
                        }
                    }
                    SettingsToggleRow(
                        title: Text("Check for updates automatically"),
                        isOn: automaticallyChecks
                    )
                    .disabled(!updater.isEnabled)
                    SettingsRow(title: Text("Help and user guide")) {
                        Link(destination: Self.guide) {
                            Text(verbatim: "warble.lorcanchinnock.com")
                        }
                    }
                }
                // Login Items can change in System Settings, which tells Warble nothing.
                .onAppear { loginItem.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
                SettingsGroup(title: Text("Acknowledgements")) {
                    SettingsRow(title: Text(verbatim: "mediaremote-adapter")) {
                        Text("BSD 3-Clause License").foregroundStyle(Native.secondary)
                    }
                    SettingsRow(title: Text(verbatim: "Sparkle")) {
                        Text("MIT License").foregroundStyle(Native.secondary)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: SettingsWindow.size.width, minHeight: SettingsWindow.size.height)
        .background(Native.panel)
        .foregroundStyle(.white)
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    /// Off and greyed out in a build with no update feed, where the updater never runs.
    private var automaticallyChecks: Binding<Bool> {
        Binding { updater.isEnabled && updater.automaticallyChecks } set: { updater.automaticallyChecks = $0 }
    }
}
