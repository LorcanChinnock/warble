import SwiftUI
import WarbleCore

/// The Settings window's sections, in sidebar order. Players and Shortcuts arrive with their features.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, notch, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .notch: String(localized: "Notch")
        case .about: String(localized: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: String(localized: "How Warble looks and where it shows.")
        case .notch: String(localized: "What the notch shows.")
        case .about: String(localized: "Version, updates and help.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notch: "menubar.rectangle"
        case .about: "info.circle"
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var section: SettingsSection = .general
}

/// A sidebar of sections beside the chosen one, in standard controls that follow the system appearance.
struct SettingsView: View {
    @Bindable private var navigation = SettingsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 200)
            Divider()
            Group {
                switch navigation.section {
                case .general: GeneralSettings()
                case .notch: NotchSettings()
                case .about: AboutSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: SettingsWindow.size.width, minHeight: SettingsWindow.size.height)
    }

    /// A list can clear its selection, but a section is always showing.
    private var selection: Binding<SettingsSection?> {
        Binding { navigation.section } set: { if let section = $0 { navigation.section = section } }
    }
}

/// A section's title and what it holds, above its form of sections.
private struct SectionPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.title2.bold())
                Text(section.subtitle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)
            Form {
                content
            }
            .formStyle(.grouped)
        }
    }
}

private struct GeneralSettings: View {
    @Setting(PreferenceKey.showMenuBarIcon) private var showMenuBarIcon: Bool
    @Setting(PreferenceKey.textSize) private var textSize: TextSize
    @Setting(PreferenceKey.stayVisibleAfterPausing) private var stayVisible: Double
    private let displays = Displays.shared

    var body: some View {
        SectionPage(section: .general) {
            Section {
                Toggle(isOn: $showMenuBarIcon) {
                    Text("Show icon in the menu bar")
                    Text("Open Warble again from Applications to bring it back.")
                }
                Picker("Text size", selection: $textSize) {
                    Text("Standard").tag(TextSize.standard)
                    Text("Large").tag(TextSize.large)
                    Text("Larger").tag(TextSize.larger)
                }
                .pickerStyle(.segmented)
            }
            Section {
                let virtual = displays.all.filter { $0.notch == nil }
                if virtual.isEmpty {
                    Text("Every display connected now has a notch.")
                        .foregroundStyle(.secondary)
                }
                ForEach(virtual, id: \.id) { display in
                    VirtualNotchPicker(display: display, name: displays.names[display.id] ?? display.id)
                }
            } header: {
                Text("Displays")
            } footer: {
                Text("On displays without a notch, and Macs without one, Warble can draw a notch of its own.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Picker(selection: $stayVisible) {
                    ForEach(IdleAfterPause.choices(including: stayVisible), id: \.self) { seconds in
                        Text(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
                            .tag(seconds)
                    }
                } label: {
                    Text("Stay visible after pausing")
                    Text("Then the notch hides until something plays.")
                }
            }
        }
    }
}

private struct NotchSettings: View {
    @Setting(PreferenceKey.idleHover) private var idleHover: IdleHover

    var body: some View {
        SectionPage(section: .notch) {
            Section {
                Picker(selection: $idleHover) {
                    Text("Last Played").tag(IdleHover.lastPlayed)
                    Text("Nothing").tag(IdleHover.nothing)
                } label: {
                    Text("When nothing is playing, hover shows")
                    Text("The notch stays hidden behind the camera until you point at it.")
                }
            } footer: {
                Text("Animations follow Reduce Motion in System Settings › Accessibility › Display.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct AboutSettings: View {
    private let updater = Updater.shared
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let guide = URL(string: "https://warble.lorcanchinnock.com/docs/")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text(verbatim: "Warble")
                    .font(.title2.bold())
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                    .padding(.top, 6)
            }
            .padding(.top, 24)
            Form {
                Section {
                    Toggle("Check for updates automatically", isOn: automaticallyChecks)
                        .disabled(!updater.isEnabled)
                    LabeledContent("Help and user guide") {
                        Link(destination: Self.guide) {
                            Text(verbatim: "warble.lorcanchinnock.com")
                        }
                    }
                }
                Section("Acknowledgements") {
                    LabeledContent {
                        Text("BSD 3-Clause License")
                    } label: {
                        Text(verbatim: "mediaremote-adapter")
                    }
                    LabeledContent {
                        Text("MIT License")
                    } label: {
                        Text(verbatim: "Sparkle")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Off and greyed out in a build with no update feed, where the updater never runs.
    private var automaticallyChecks: Binding<Bool> {
        Binding { updater.isEnabled && updater.automaticallyChecks } set: { updater.automaticallyChecks = $0 }
    }
}
