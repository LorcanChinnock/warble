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

/// A column of sections beside the chosen one, always dark like the notch.
struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarRow(section: section, isSelected: navigation.section == section) {
                        withAnimation(reduceMotion ? Native.fade : Native.morph) { navigation.section = section }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            // Clear of the title bar's buttons, which the content runs under.
            .padding(.top, 48)
            .frame(width: 200)
            Rectangle().fill(Native.track).frame(width: 1)
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
        .background(Native.panel)
        .foregroundStyle(.white)
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // A fixed width, so every name starts at the same place whatever its symbol's width.
                Image(systemName: section.symbol)
                    .frame(width: 22, height: 16)
                    .accessibilityHidden(true)
                Text(section.title)
            }
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(Native.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Native.selection)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.notch)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A section's title and what it holds, above its groups of rows.
private struct SectionPage<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(section.subtitle)
                        .foregroundStyle(Native.secondary)
                }
                content
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            SettingsGroup {
                SettingsToggleRow(
                    title: Text("Open at login"),
                    detail: loginItem.needsApproval
                        ? Text("Turned off in System Settings. Turn Warble on in Login Items to open it at login again.")
                        : Text("Warble opens when you log in, so the notch is there after a restart."),
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
                    .frame(width: 270)
                }
            }
            // Login Items can change in System Settings, which tells Warble nothing.
            .onAppear { loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
            SettingsGroup(
                title: Text("Displays"),
                footer: Text("On displays without a notch, and Macs without one, Warble can draw a notch of its own.")
            ) {
                let virtual = displays.all.filter { $0.notch == nil }
                if virtual.isEmpty {
                    SettingsRow(title: Text("Every display connected now has a notch.")) {}
                }
                ForEach(virtual, id: \.id) { display in
                    VirtualNotchRow(display: display, name: displays.names[display.id] ?? display.id)
                }
            }
            SettingsGroup {
                SettingsMenuRow(
                    title: Text("Stay visible after pausing"),
                    detail: Text("Then the notch hides until something plays."),
                    selection: $stayVisible,
                    options: IdleAfterPause.choices(including: stayVisible).map { seconds in
                        WarbleOption(value: seconds, title: Text(verbatim: Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))))
                    }
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

private struct NotchSettings: View {
    @Setting(PreferenceKey.idleHover) private var idleHover: IdleHover
    @Setting(PreferenceKey.trackChangeToast) private var trackChangeToast: Bool
    @Setting(PreferenceKey.toastsInFullScreen) private var toastsInFullScreen: Bool
    @Setting(PreferenceKey.lyrics) private var lyrics: Bool
    @Setting(PreferenceKey.swipeToSkip) private var swipeToSkip: Bool
    @Setting(PreferenceKey.dragArtOut) private var dragArtOut: Bool
    @Setting(PreferenceKey.podcastSkips) private var podcastSkips: Bool
    @Setting(PreferenceKey.sleepTimer) private var sleepTimer: Bool
    @Setting(PreferenceKey.resumeBrowserTabs) private var resumeBrowserTabs: Bool
    @Setting(PreferenceKey.hideFromCapture) private var hideFromCapture: Bool
    @Setting(PreferenceKey.virtualTitle) private var virtualTitle: Bool

    var body: some View {
        SectionPage(section: .notch) {
            SettingsGroup(footer: Text("Animations follow Reduce Motion in System Settings › Accessibility › Display.")) {
                SettingsMenuRow(
                    title: Text("When nothing is playing, hover shows"),
                    detail: Text("The notch stays hidden behind the camera until you point at it."),
                    selection: $idleHover,
                    options: [
                        WarbleOption(value: .lastPlayed, title: Text("Last Played")),
                        WarbleOption(value: .nothing, title: Text("Nothing")),
                    ]
                )
                SettingsToggleRow(
                    title: Text("Show a message when the track changes"),
                    detail: Text("The new song's title and artist slide out of the notch for two seconds."),
                    isOn: $trackChangeToast
                )
                SettingsToggleRow(
                    title: Text("Show it over full-screen apps too"),
                    detail: Text("Only the message shows. The notch stays out of the way."),
                    isOn: $toastsInFullScreen
                )
                .disabled(!trackChangeToast)
            }
            SettingsGroup(footer: Text("A long title fades out and scrolls once when the song changes, unless Reduce Motion is on. The track-change message skips a virtual notch that shows the title, since the title says the same.")) {
                SettingsToggleRow(
                    title: Text("Show the title in a virtual notch"),
                    detail: Text("On a display without a notch, the song's title shows in the middle."),
                    isOn: $virtualTitle
                )
            }
            SettingsGroup(footer: Text("To find a song's lyrics, Warble sends its title, artist, album and length to LRCLIB, a free lyrics library. Nothing is sent while this is off.")) {
                SettingsToggleRow(
                    title: Text("Show lyrics under the notch"),
                    detail: Text("The line being sung, while a song plays."),
                    isOn: $lyrics
                )
            }
            SettingsGroup(footer: Text("Needs a trackpad, or a Magic Mouse, where you swipe with one finger. Scrolling up and down over the notch still changes the volume.")) {
                SettingsToggleRow(
                    title: Text("Swipe over the notch to skip"),
                    detail: Text("Swipe left with two fingers for the next song, or right to go back."),
                    isOn: $swipeToSkip
                )
            }
            SettingsGroup(footer: Text("Drop it in a message, a note or a folder. It brings the picture, and a link to the song when the app playing gives one. A click on the art still opens the app.")) {
                SettingsToggleRow(
                    title: Text("Drag the album art out of the player"),
                    detail: Text("Drag the art into another app to share the song."),
                    isOn: $dragArtOut
                )
            }
            SettingsGroup(footer: Text("These buttons take the place of previous and next. Songs keep previous and next either way.")) {
                SettingsToggleRow(
                    title: Text("Skip by seconds in podcasts"),
                    detail: Text("Go back 15 seconds or forward 30 in a podcast or audiobook."),
                    isOn: $podcastSkips
                )
            }
            SettingsGroup(footer: Text("The timer button sits beside the output button. A timer stops if you pause, and it never starts by itself.")) {
                SettingsToggleRow(
                    title: Text("Show a sleep timer in the player"),
                    detail: Text("Pause after 15 minutes, 30 minutes, an hour or at the end of the track."),
                    isOn: $sleepTimer
                )
            }
            SettingsGroup(footer: Text("macOS asks once for each browser. Works with Safari, Chrome, Brave, Edge, Arc and Vivaldi. Without it, or in another browser, the button opens the browser.")) {
                SettingsToggleRow(
                    title: Text("Reopen browser tracks from the idle card"),
                    detail: Text("Remember the page a track played on, so the play button can open it again."),
                    isOn: $resumeBrowserTabs
                )
            }
            SettingsGroup(footer: Text("This covers sharing your screen in a call, screen recordings and screenshots.")) {
                SettingsToggleRow(
                    title: Text("Hide from screen sharing and recordings"),
                    detail: Text("You still see the notch. People watching your screen don't."),
                    isOn: $hideFromCapture
                )
            }
        }
    }
}

private struct ShortcutsSettings: View {
    @Environment(ShortcutRecorder.self) private var recorder

    var body: some View {
        SectionPage(section: .shortcuts) {
            SettingsGroup(footer: Text("The media keys on your keyboard already work. These are for when you want another key.")) {
                ForEach(WarbleAction.allCases, id: \.self) { action in
                    ShortcutRow(action: action, recorder: recorder)
                }
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
