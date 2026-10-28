import ServiceManagement
import SwiftUI
import WarbleCore
import WarbleModel

/// The Settings window's one page, in the website's look and following the system's light or dark appearance: what Warble
/// is, the notch and how it looks, whether Warble opens at login, and updates.
struct SettingsView: View {
    @Environment(Updater.self) private var updater
    @Environment(LoginItem.self) private var loginItem
    @Environment(NotchSettings.self) private var notchSettings
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let guide = URL(string: "https://warble.lorcanchinnock.com/docs/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "Warble")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(Warm.ink)
                        Text("Version \(Self.version)")
                            .font(.system(size: 11, weight: .heavy))
                            .textCase(.uppercase)
                            .tracking(0.9)
                            .foregroundStyle(Warm.onAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .background(Warm.yellow, in: Capsule())
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .buttonStyle(.warbleQuiet)
                        .disabled(!updater.canCheckForUpdates)
                }
                // Clear of the title bar's buttons, which the content runs under.
                .padding(.top, 44)
                VStack(alignment: .leading, spacing: 8) {
                    NotchPreview(showsTitle: notchSettings.showsVirtualTitle, showsGlow: notchSettings.showsGlow, pauseDelay: notchSettings.pauseDelay, cardSize: notchSettings.cardSize, visibility: notchSettings.virtualVisibility)
                    Text("How the notch looks, with a made-up song. Point at it to open it.")
                        .font(.footnote)
                        .foregroundStyle(Warm.secondary)
                        .padding(.horizontal, 14)
                }
                SettingsGroup(title: Text("Notch"), symbol: "music.note") {
                    SettingsChoiceRow(
                        title: Text("Stay visible after pausing"),
                        detail: Text("How long the notch keeps showing a paused song before it goes quiet."),
                        selection: Binding { notchSettings.pauseDelay } set: { notchSettings.pauseDelay = $0 },
                        options: [
                            (.tenSeconds, Text("10 seconds")),
                            (.oneMinute, Text("1 minute")),
                            (.always, Text("Always")),
                        ]
                    )
                    SettingsChoiceRow(
                        title: Text("Opened notch size"),
                        detail: Text("How big the notch is when you open it. The closed notch stays the same size."),
                        selection: Binding { notchSettings.cardSize } set: { notchSettings.cardSize = $0 },
                        options: [
                            (.small, Text("Small")),
                            (.standard, Text("Default")),
                            (.large, Text("Large")),
                        ]
                    )
                    SettingsChoiceRow(
                        title: Text("Notch on external displays"),
                        detail: Text("On a display without a notch, or with the lid closed, when Warble draws a notch of its own."),
                        selection: Binding { notchSettings.virtualVisibility } set: { notchSettings.virtualVisibility = $0 },
                        options: [
                            (.whenPlaying, Text("Only when playing")),
                            (.always, Text("Always")),
                            (.off, Text("Off")),
                        ]
                    )
                    SettingsToggleRow(
                        title: Text("Show the title in a virtual notch"),
                        detail: Text("On a display without a notch, the middle of the notch shows the song's title and artist."),
                        isOn: Binding { notchSettings.showsVirtualTitle } set: { notchSettings.showsVirtualTitle = $0 }
                    )
                    SettingsToggleRow(
                        title: Text("Album-art glow"),
                        detail: Text("The open notch glows in the colours of the album art. Turn it off for a plain black notch."),
                        isOn: Binding { notchSettings.showsGlow } set: { notchSettings.showsGlow = $0 }
                    )
                }
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
                                .font(.body.weight(.semibold))
                                .underline(color: Warm.pink)
                        }
                    }
                }
                // Login Items can change in System Settings, which tells Warble nothing.
                .onAppear { loginItem.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
                SettingsGroup(title: Text("Acknowledgements")) {
                    SettingsRow(title: Text(verbatim: "mediaremote-adapter")) {
                        Text("BSD 3-Clause License").foregroundStyle(Warm.secondary)
                    }
                    SettingsRow(title: Text(verbatim: "Sparkle")) {
                        Text("MIT License").foregroundStyle(Warm.secondary)
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: SettingsWindow.size.width, minHeight: SettingsWindow.size.height)
        .background { Rectangle().fill(Warm.window).ignoresSafeArea() }
        .foregroundStyle(Warm.ink)
    }

    /// Off and greyed out in a build with no update feed, where the updater never runs.
    private var automaticallyChecks: Binding<Bool> {
        Binding { updater.isEnabled && updater.automaticallyChecks } set: { updater.automaticallyChecks = $0 }
    }
}
