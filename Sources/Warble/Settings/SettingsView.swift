import ServiceManagement
import SwiftUI
import WarbleCore

/// The Settings window's sections, in sidebar order. Players arrives with its feature.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, notch, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .notch: String(localized: "Notch")
        case .shortcuts: String(localized: "Shortcuts")
        case .about: String(localized: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .general: String(localized: "How Warble looks and where it shows.")
        case .notch: String(localized: "What the notch shows.")
        case .shortcuts: String(localized: "Control playback from any app. None are set until you add one.")
        case .about: String(localized: "Version, updates and help.")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notch: "menubar.rectangle"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    var section: SettingsSection = .general
}

/// A sidebar of sections beside the chosen one, in standard controls that follow the system appearance.
struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation

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
                case .shortcuts: ShortcutsSettings()
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
    @Environment(Displays.self) private var displays
    @Environment(LoginItem.self) private var loginItem

    var body: some View {
        SectionPage(section: .general) {
            Section {
                Toggle(isOn: Binding { loginItem.isEnabled } set: { loginItem.set($0) }) {
                    Text("Open at login")
                    if loginItem.needsApproval {
                        Text("Turned off in System Settings. Turn Warble on in Login Items to open it at login again.")
                    } else {
                        Text("Warble opens when you log in, so the notch is there after a restart.")
                    }
                }
                .accessibilityLabel(Text("Open at login"))
                .accessibilityHint(loginItem.needsApproval
                    ? Text("Turned off in System Settings. Turn Warble on in Login Items to open it at login again.")
                    : Text("Warble opens when you log in, so the notch is there after a restart."))
                if loginItem.needsApproval {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Toggle(isOn: $showMenuBarIcon) {
                    Text("Show icon in the menu bar")
                    Text("Open Warble again from Applications to bring it back.")
                }
                .accessibilityLabel(Text("Show icon in the menu bar"))
                .accessibilityHint(Text("Open Warble again from Applications to bring it back."))
                Picker("Text size", selection: $textSize) {
                    Text("Standard").tag(TextSize.standard)
                    Text("Large").tag(TextSize.large)
                    Text("Larger").tag(TextSize.larger)
                }
                .pickerStyle(.segmented)
            }
            // Login Items can change in System Settings, which tells Warble nothing.
            .onAppear { loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
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
                .accessibilityLabel(Text("Stay visible after pausing"))
                .accessibilityHint(Text("Then the notch hides until something plays."))
            }
        }
    }
}

private struct NotchSettings: View {
    @Setting(PreferenceKey.idleHover) private var idleHover: IdleHover
    @Setting(PreferenceKey.trackChangeToast) private var trackChangeToast: Bool
    @Setting(PreferenceKey.toastsInFullScreen) private var toastsInFullScreen: Bool
    @Setting(PreferenceKey.lyrics) private var lyrics: Bool
    @Setting(PreferenceKey.swipeToSkip) private var swipeToSkip: Bool
    @Setting(PreferenceKey.dragArtOut) private var dragArtOut: Bool
    @Setting(PreferenceKey.podcastSkips) private var podcastSkips: Bool
    @Setting(PreferenceKey.sleepTimer) private var sleepTimer: Bool
    @Setting(PreferenceKey.hideFromCapture) private var hideFromCapture: Bool
    @Setting(PreferenceKey.virtualTitle) private var virtualTitle: Bool

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
                .accessibilityLabel(Text("When nothing is playing, hover shows"))
                .accessibilityHint(Text("The notch stays hidden behind the camera until you point at it."))
                Toggle(isOn: $trackChangeToast) {
                    Text("Show a message when the track changes")
                    Text("The new song's title and artist slide out of the notch for two seconds.")
                }
                .accessibilityLabel(Text("Show a message when the track changes"))
                .accessibilityHint(Text("The new song's title and artist slide out of the notch for two seconds."))
                Toggle(isOn: $toastsInFullScreen) {
                    Text("Show it over full-screen apps too")
                    Text("Only the message shows. The notch stays out of the way.")
                }
                .disabled(!trackChangeToast)
                .accessibilityLabel(Text("Show it over full-screen apps too"))
                .accessibilityHint(Text("Only the message shows. The notch stays out of the way."))
            } footer: {
                Text("Animations follow Reduce Motion in System Settings › Accessibility › Display.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $virtualTitle) {
                    Text("Show the title in a virtual notch")
                    Text("On a display without a notch, the song's title shows in the middle.")
                }
                .accessibilityLabel(Text("Show the title in a virtual notch"))
                .accessibilityHint(Text("On a display without a notch, the song's title shows in the middle."))
            } footer: {
                Text("A long title fades out and scrolls once when the song changes, unless Reduce Motion is on. The track-change message skips a virtual notch that shows the title, since the title says the same.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $lyrics) {
                    Text("Show lyrics under the notch")
                    Text("The line being sung, while a song plays.")
                }
                .accessibilityLabel(Text("Show lyrics under the notch"))
                .accessibilityHint(Text("The line being sung, while a song plays."))
            } footer: {
                Text("To find a song's lyrics, Warble sends its title, artist, album and length to LRCLIB, a free lyrics library. Nothing is sent while this is off.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $swipeToSkip) {
                    Text("Swipe over the notch to skip")
                    Text("Swipe left with two fingers for the next song, or right to go back.")
                }
                .accessibilityLabel(Text("Swipe over the notch to skip"))
                .accessibilityHint(Text("Swipe left with two fingers for the next song, or right to go back."))
            } footer: {
                Text("Needs a trackpad, or a Magic Mouse, where you swipe with one finger. Scrolling up and down over the notch still changes the volume.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $dragArtOut) {
                    Text("Drag the album art out of the player")
                    Text("Drag the art into another app to share the song.")
                }
                .accessibilityLabel(Text("Drag the album art out of the player"))
                .accessibilityHint(Text("Drag the art into another app to share the song."))
            } footer: {
                Text("Drop it in a message, a note or a folder. It brings the picture, and a link to the song when the app playing gives one. A click on the art still opens the app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $podcastSkips) {
                    Text("Skip by seconds in podcasts")
                    Text("Go back 15 seconds or forward 30 in a podcast or audiobook.")
                }
                .accessibilityLabel(Text("Skip by seconds in podcasts"))
                .accessibilityHint(Text("Go back 15 seconds or forward 30 in a podcast or audiobook."))
            } footer: {
                Text("These buttons take the place of previous and next. Songs keep previous and next either way.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $sleepTimer) {
                    Text("Show a sleep timer in the player")
                    Text("Pause after 15 minutes, 30 minutes, an hour or at the end of the track.")
                }
                .accessibilityLabel(Text("Show a sleep timer in the player"))
                .accessibilityHint(Text("Pause after 15 minutes, 30 minutes, an hour or at the end of the track."))
            } footer: {
                Text("The timer button sits beside the output button. A timer stops if you pause, and it never starts by itself.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(isOn: $hideFromCapture) {
                    Text("Hide from screen sharing and recordings")
                    Text("You still see the notch. People watching your screen don't.")
                }
                .accessibilityLabel(Text("Hide from screen sharing and recordings"))
                .accessibilityHint(Text("You still see the notch. People watching your screen don't."))
            } footer: {
                Text("This covers sharing your screen in a call, screen recordings and screenshots.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ShortcutsSettings: View {
    @Environment(ShortcutRecorder.self) private var recorder

    var body: some View {
        SectionPage(section: .shortcuts) {
            Section {
                ForEach(WarbleAction.allCases, id: \.self) { action in
                    ShortcutRow(action: action, recorder: recorder)
                }
            } footer: {
                Text("The media keys on your keyboard already work. These are for when you want another key.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Switching pages or closing the window stops a recording, so no key stays caught.
        .onDisappear { recorder.reset() }
    }
}

private struct AboutSettings: View {
    @Environment(Updater.self) private var updater
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
                        // A switch in a form reports no name of its own, so VoiceOver reads it as "switch".
                        .accessibilityLabel(Text("Check for updates automatically"))
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
