import ServiceManagement
import SwiftUI
import WarbleCore
import WarbleModel

/// The Notch tab: the preview, and every setting that changes what the notch shows or how it looks.
struct NotchTab: View {
    @Environment(NotchSettings.self) private var notchSettings

    var body: some View {
        @Bindable var settings = notchSettings
        SettingsPage {
            VStack(alignment: .leading, spacing: 8) {
                NotchPreview(showsTitle: settings.showsVirtualTitle, notchFont: settings.notchFont, pauseDelay: settings.pauseDelay, cardSize: settings.cardSize, visibility: settings.virtualVisibility, showsFavourite: settings.showsFavourite)
                Text("Point at the preview to open it. Its buttons don't control your music.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        } form: {
            Section("When a song is paused") {
                let pause = Text("Stay visible after pausing")
                let pauseDetail = Text("How long a paused song stays before the notch goes quiet.")
                Picker(selection: $settings.pauseDelay) {
                    Text("10 seconds").tag(PauseDelay.tenSeconds)
                    Text("1 minute").tag(PauseDelay.oneMinute)
                    Text("Always").tag(PauseDelay.always)
                } label: {
                    pause
                    pauseDetail
                }
                .described(pause, pauseDetail)
            }

            Section("Opened notch") {
                Picker("Size", selection: $settings.cardSize) {
                    Text("Small").tag(CardSize.small)
                    Text("Default").tag(CardSize.standard)
                    Text("Large").tag(CardSize.large)
                }
                .pickerStyle(.segmented)
                .accentSwitch()
                // A one-line row is named by its label, but a grouped form leaves these controls reporting only their
                // value, so name them outright.
                .accessibilityLabel(Text("Size"))

                Picker("Song title font", selection: $settings.notchFont) {
                    Text("Default").tag(NotchFont.system)
                    Text("Rounded").tag(NotchFont.rounded)
                    Text("Mono").tag(NotchFont.monospaced)
                }
                .accessibilityLabel(Text("Song title font"))

                let heart = Text("Heart for Music's Favourites")
                let heartDetail = Text("While Music plays, a heart beside the title adds the song to your Favourites.")
                Toggle(isOn: $settings.showsFavourite) {
                    heart
                    heartDetail
                }
                .accentSwitch()
                .described(heart, heartDetail)
            }

            Section {
                let external = Text("Show a notch")
                let externalDetail = Text("On an external display, or with the lid closed, Warble draws one.")
                Picker(selection: $settings.virtualVisibility) {
                    Text("Only when playing").tag(VirtualNotchVisibility.whenPlaying)
                    Text("Always").tag(VirtualNotchVisibility.always)
                    Text("Off").tag(VirtualNotchVisibility.off)
                } label: {
                    external
                    externalDetail
                }
                .described(external, externalDetail)

                let title = Text("Song title in the notch")
                let titleDetail = Text("The middle of the notch shows the title and artist.")
                Toggle(isOn: $settings.showsVirtualTitle) {
                    title
                    titleDetail
                }
                .accentSwitch()
                .described(title, titleDetail)
            } header: {
                Text("Displays without a notch")
            } footer: {
                Text("Your MacBook's own notch never changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The General tab: whether Warble opens at login, and where to find help.
struct GeneralTab: View {
    @Environment(LoginItem.self) private var loginItem
    private static let guide = URL(string: "https://warble.lorcanchinnock.com/docs/")!

    var body: some View {
        SettingsPage {
            Section {
                let login = Text("Open at login")
                let loginDetail = Text("Turned off in System Settings. Turn Warble on in Login Items to open it at login again.")
                Toggle(isOn: Binding { loginItem.isEnabled } set: { loginItem.set($0) }) {
                    login
                    if loginItem.needsApproval {
                        loginDetail
                    }
                }
                .accentSwitch()
                .described(login, loginItem.needsApproval ? loginDetail : nil)
                if loginItem.needsApproval {
                    LabeledContent("Login Items") {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }
            Section {
                LabeledContent("Help and user guide") {
                    Link(destination: Self.guide) {
                        Text(verbatim: "warble.lorcanchinnock.com")
                    }
                }
            }
        }
        // Login Items can change in System Settings, which tells Warble nothing.
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

/// The About tab: what Warble is and which version, updates, and the acknowledgements.
struct AboutTab: View {
    @Environment(Updater.self) private var updater
    private static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    @State private var pecks = 0
    @State private var streak = (count: 0, last: Date.distantPast)
    @State private var songs = 0
    /// What the version line says while the icon sings, and the task that puts it back.
    @State private var song: String?
    @State private var singing: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPage {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Warble")
                        .font(.system(size: 20, weight: .bold))
                    (song.map { Text(verbatim: $0) } ?? Text("Version \(Self.version)"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        } form: {
            Section {
                Toggle("Check for updates automatically", isOn: automaticallyChecks)
                    .accentSwitch()
                    .disabled(!updater.isEnabled)
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
        .onDisappear { singing?.cancel() }
    }

    private var icon: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .keyframeAnimator(initialValue: 0.0, trigger: pecks) { icon, angle in
                icon.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-10, duration: 0.08)
                    CubicKeyframe(8, duration: 0.1)
                    CubicKeyframe(-4, duration: 0.1)
                    SpringKeyframe(0, duration: 0.25)
                }
            }
            .keyframeAnimator(initialValue: 0.0, trigger: songs) { icon, lift in
                icon.offset(y: lift)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-14, duration: 0.14)
                    CubicKeyframe(0, duration: 0.14)
                    CubicKeyframe(-10, duration: 0.12)
                    SpringKeyframe(0, duration: 0.3, spring: .bouncy)
                }
            }
            .overlay(alignment: .top) { if !reduceMotion { Notes(trigger: songs) } }
            .onTapGesture { peck() }
            .accessibilityHidden(true)
    }

    private static let lines = [
        "Tweet tweet ♪", "Chirp chirp!", "Pretty bird.", "Warble warble ♫", "Polly wants a playlist",
        "Is this thing on?", "Now playing: birdsong", "La la la ♪", "Early bird, best track", "Cheep cheep",
        "Shh, I'm singing", "Skip? Never.", "Feathers ruffled", "Nice pecking!", "Mic check, one two",
        "Bird is the word", "Hold that note…", "Encore!", "A little off key ♭", "Ooh, a worm ♪",
    ]

    /// A click on the icon wobbles it; five in a row, each within a second of the last, make it sing. While it sings,
    /// further clicks only wobble it and count for nothing, so spamming it can't stack songs, sounds or timers.
    private func peck() {
        let now = Date.now
        streak = (now.timeIntervalSince(streak.last) < 1 ? streak.count + 1 : 1, now)
        if !reduceMotion { pecks += 1 }
        guard singing == nil else {
            streak.count = 0
            return
        }
        guard streak.count == 5 else { return }
        streak.count = 0
        songs += 1
        Chirp.play()
        withAnimation(Native.fade) { song = Self.lines.filter { $0 != song }.randomElement() }
        singing = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Native.fade) { song = nil }
            singing = nil
        }
    }

    /// Off and greyed out in a build with no update feed, where the updater never runs.
    private var automaticallyChecks: Binding<Bool> {
        Binding { updater.isEnabled && updater.automaticallyChecks } set: { updater.automaticallyChecks = $0 }
    }
}

/// A tab's layout: an optional header above a grouped form, at the window's insets. The form doesn't scroll, because the
/// window fits it.
private struct SettingsPage<Header: View, Content: View>: View {
    let header: Header
    let form: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder form: () -> Content) {
        self.header = header()
        self.form = form()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
            Form { form }
                .formStyle(.grouped)
                .scrollDisabled(true)
        }
    }
}

private extension SettingsPage where Header == EmptyView {
    init(@ViewBuilder form: () -> Content) {
        self.init(header: { EmptyView() }, form: form)
    }
}

private extension View {
    /// Names a row whose label has two `Text`s, since such a row reports no VoiceOver name of its own: the title as its
    /// label and the line under it as its hint.
    func described(_ title: Text, _ detail: Text?) -> some View {
        accessibilityLabel(title)
            .accessibilityHint(detail ?? Text(verbatim: ""))
    }

    /// The icon's yellow on a switch that's on or a chosen segment. It's set on each control rather than as the app's
    /// accent colour, because the system draws the selected toolbar tab's label in the accent, and text is never yellow.
    func accentSwitch() -> some View {
        tint(Color.warbleYellow)
    }
}

/// A few notes that drift up from the icon and fade, each on its own sway, once `trigger` changes. Nothing runs before then.
private struct Notes: View {
    let trigger: Int
    private static let glyphs = ["♪", "♫", "♪", "♫", "♪"]
    /// The website's pink and sky.
    private static let colours = [Color(hex: 0xFF7DB4), Color(hex: 0x7FBEDF)]

    private struct Flight {
        var rise = 0.0
        var sway = 0.0
        var opacity = 0.0
    }

    var body: some View {
        ZStack {
            ForEach(Self.glyphs.indices, id: \.self) { index in
                let side = index.isMultiple(of: 2) ? 1.0 : -1.0
                Text(verbatim: Self.glyphs[index])
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.colours[index % 2])
                    .keyframeAnimator(initialValue: Flight(), trigger: trigger) { note, flight in
                        note
                            .offset(x: flight.sway + side * Double(index) * 6, y: -flight.rise)
                            .opacity(flight.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.rise) {
                            LinearKeyframe(0, duration: Double(index) * 0.18)
                            CubicKeyframe(90, duration: 1.4)
                        }
                        KeyframeTrack(\.sway) {
                            LinearKeyframe(0, duration: Double(index) * 0.18)
                            CubicKeyframe(side * 14, duration: 0.7)
                            CubicKeyframe(side * -10, duration: 0.7)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: Double(index) * 0.18)
                            LinearKeyframe(1, duration: 0.2)
                            LinearKeyframe(1, duration: 0.7)
                            LinearKeyframe(0, duration: 0.5)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
