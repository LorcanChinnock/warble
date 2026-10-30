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
    /// How wide the page grows when the window is made wider.
    private static let pageWidth: CGFloat = 640
    private static let guide = URL(string: "https://warble.lorcanchinnock.com/docs/")!
    /// Whether the page is moving, so the preview under the pointer doesn't open mid-scroll.
    @State private var isScrolling = false
    @State private var pecks = 0
    @State private var streak = (count: 0, last: Date.distantPast)
    @State private var songs = 0
    /// What the version line says while the icon sings, and the task that puts it back.
    @State private var song: String?
    @State private var singing: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            pinned
            ScrollView {
                VStack(spacing: 20) {
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
                        SettingsChoiceRow(
                            title: Text("Song title font"),
                            detail: Text("The typeface the notch sets the song's title in."),
                            selection: Binding { notchSettings.notchFont } set: { notchSettings.notchFont = $0 },
                            options: [
                                (.system, Text("Default")),
                                (.rounded, Text("Rounded")),
                                (.monospaced, Text("Mono")),
                            ]
                        )
                    }
                    SettingsGroup(title: Text("General"), symbol: "gearshape", tint: Warm.sky) {
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
                    SettingsGroup(title: Text("Acknowledgements"), symbol: "heart", tint: Warm.pink) {
                        SettingsRow(title: Text(verbatim: "mediaremote-adapter")) {
                            Text("BSD 3-Clause License").foregroundStyle(Warm.secondary)
                        }
                        SettingsRow(title: Text(verbatim: "Sparkle")) {
                            Text("MIT License").foregroundStyle(Warm.secondary)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 6)
                .padding(.bottom, 30)
                .frame(maxWidth: Self.pageWidth)
                .frame(maxWidth: .infinity)
            }
            // The page slides under a short fade at the pinned preview's foot rather than being cut.
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Warm.window)
                    .frame(height: 14)
                    .mask {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    }
                    .allowsHitTesting(false)
            }
            .onScrollPhaseChange { _, phase in isScrolling = phase != .idle }
        }
        .frame(minWidth: SettingsWindow.minimumSize.width, minHeight: SettingsWindow.minimumSize.height)
        .onDisappear { singing?.cancel() }
        .background { Rectangle().fill(Warm.window).ignoresSafeArea() }
        .foregroundStyle(Warm.ink)
    }

    /// The name, version and preview, which stay put while the settings scroll under them, so each change shows at once.
    private var pinned: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Warble")
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(Warm.ink)
                    // Plain, like the website's meta line: yellow is for what is on or chosen.
                    (song.map { Text(verbatim: $0) } ?? Text("Version \(Self.version)"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                        .foregroundStyle(Warm.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .buttonStyle(.warbleQuiet)
                    .disabled(!updater.canCheckForUpdates)
            }
            // Clear of the bar over the title bar.
            .padding(.top, 44)
            VStack(alignment: .leading, spacing: 8) {
                NotchPreview(showsTitle: notchSettings.showsVirtualTitle, notchFont: notchSettings.notchFont, pauseDelay: notchSettings.pauseDelay, cardSize: notchSettings.cardSize, visibility: notchSettings.virtualVisibility, isScrolling: isScrolling)
                Text("How the notch looks, with the song that's playing. Point at it to open it.")
                    .font(.footnote)
                    .foregroundStyle(Warm.secondary)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
        .frame(maxWidth: Self.pageWidth)
        .frame(maxWidth: .infinity)
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

/// A few notes that drift up from the icon and fade, each on its own sway, once `trigger` changes. Nothing runs before then.
private struct Notes: View {
    let trigger: Int
    private static let glyphs = ["♪", "♫", "♪", "♫", "♪"]

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
                    .foregroundStyle(index.isMultiple(of: 2) ? Warm.pink : Warm.sky)
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
