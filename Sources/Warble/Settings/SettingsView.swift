import ServiceManagement
import SwiftUI
import WarbleCore

/// The Settings window's pages, in tab order. Players arrives with its feature.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, about

    var id: String { rawValue }

    var title: Text {
        switch self {
        case .general: Text("General")
        case .about: Text("About")
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general
}

/// A row of tabs above the chosen page, always dark like the notch.
struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

    var body: some View {
        VStack(spacing: 0) {
            WarbleSegmented(
                selection: Binding { navigation.section } set: { navigation.section = $0 },
                options: SettingsSection.allCases.map { WarbleOption(value: $0, title: $0.title) },
                label: Text("Settings pages")
            )
            .frame(width: 300)
            // Clear of the title bar's buttons, which the content runs under.
            .padding(.top, 38)
            .padding(.bottom, 14)
            Group {
                switch navigation.section {
                case .general: GeneralSettings()
                case .about: AboutSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: SettingsWindow.size.width, minHeight: SettingsWindow.size.height)
        .background(Native.panel)
        .foregroundStyle(.white)
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

/// A page's groups of rows, scrolling when they don't fit.
private struct SectionPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GeneralSettings: View {
    @Setting(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon: Bool
    @Setting(PreferenceKey.textSize) private var textSize: TextSize
    @Setting(PreferenceKey.stayVisibleAfterPausing) private var stayVisible: Double
    @Setting(PreferenceKey.trackChangeToast) private var trackChangeToast: Bool
    @Environment(LoginItem.self) private var loginItem

    var body: some View {
        SectionPage {
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
                    title: Text("Show icon in the menu bar"),
                    detail: Text("Open Warble again from Applications to bring it back."),
                    isOn: $showMenuBarIcon
                )
                SettingsRow(title: Text("Text size"), speaksForControl: true) {
                    WarbleSegmented(selection: $textSize, options: [
                        WarbleOption(value: .standard, title: Text("Standard")),
                        WarbleOption(value: .large, title: Text("Large")),
                        WarbleOption(value: .larger, title: Text("Larger")),
                    ], label: Text("Text size"))
                    .frame(width: 300)
                }
            }
            // Login Items can change in System Settings, which tells Warble nothing.
            .onAppear { loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
            SettingsGroup(title: Text("Notch")) {
                SettingsMenuRow(
                    title: Text("Stay visible after pausing"),
                    detail: Text("Then the notch hides until something plays."),
                    selection: $stayVisible,
                    options: IdleAfterPause.choices(including: stayVisible).map { seconds in
                        WarbleOption(value: seconds, title: Text(verbatim: Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))))
                    }
                )
                SettingsToggleRow(
                    title: Text("Show a message when the song changes"),
                    detail: Text("The new song's title and artist slide out of the notch for two seconds."),
                    isOn: $trackChangeToast
                )
            }
            DisplaysGroup()
        }
    }
}

/// A rule for each display without a notch, and the title that goes in the middle of a notch Warble draws.
private struct DisplaysGroup: View {
    @Setting(PreferenceKey.virtualTitle) private var virtualTitle: Bool
    @Environment(Displays.self) private var displays

    var body: some View {
        let virtual = displays.all.filter { $0.notch == nil }
        SettingsGroup(
            title: Text("Displays"),
            footer: Text("On displays without a notch, and Macs without one, Warble can draw a notch of its own.")
        ) {
            if virtual.isEmpty {
                SettingsRow(title: Text("Every display connected now has a notch.")) {}
            }
            ForEach(virtual, id: \.id) { display in
                VirtualNotchRow(display: display, name: displays.names[display.id] ?? display.id)
            }
            if !virtual.isEmpty {
                SettingsToggleRow(
                    title: Text("Show the title in a virtual notch"),
                    detail: Text("The song's title shows in the middle."),
                    isOn: $virtualTitle
                )
            }
        }
    }
}

private struct VirtualNotchRow: View {
    let display: NotchDisplay
    let name: String
    @Setting(PreferenceKey.virtualNotch) private var rules: [String: String]

    var body: some View {
        SettingsRow(title: Text(verbatim: name), speaksForControl: true) {
            WarbleMenuPicker(
                selection: $rules.virtualNotchRule(for: display),
                options: VirtualNotchRule.allCases.map { WarbleOption(value: $0, title: $0.label) },
                label: Text(verbatim: name)
            )
        }
    }
}

private struct AboutSettings: View {
    @Environment(Updater.self) private var updater
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
                .padding(.top, 24)
                SettingsGroup {
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
    }

    /// Off and greyed out in a build with no update feed, where the updater never runs.
    private var automaticallyChecks: Binding<Bool> {
        Binding { updater.isEnabled && updater.automaticallyChecks } set: { updater.automaticallyChecks = $0 }
    }
}
