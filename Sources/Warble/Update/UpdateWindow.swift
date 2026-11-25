import AppKit
import Observation
import SwiftUI
import WarbleCore
import WarbleModel

/// What the update window shows, which `UpdateUserDriver` moves along as Sparkle reports each step.
@MainActor
@Observable
final class UpdateWindowModel {
    struct Actions {
        var install: @MainActor () -> Void = {}
        var remindLater: @MainActor () -> Void = {}
        var skip: @MainActor () -> Void = {}
        var cancel: @MainActor () -> Void = {}
        var hide: @MainActor () -> Void = {}
        var relaunch: @MainActor () -> Void = {}
        var installOnQuit: @MainActor () -> Void = {}
        var later: @MainActor () -> Void = {}
        var setInstallsAutomatically: @MainActor (Bool) -> Void = { _ in }
    }

    var phase: UpdatePhase = .checking
    var offer: UpdateOffer?
    /// The release notes for every version since the installed one.
    var notes = ReleaseNotes(versions: [])
    var buttons: UpdateOfferButtons?
    var download = UpdateDownloadProgress()
    /// "About 5 seconds left", worked out as each piece of the download arrives, so nothing ticks while it waits.
    var secondsLeft: Int?
    /// The offer's "Install updates automatically from now on", which is About's Install updates automatically.
    var installsAutomatically = false {
        didSet {
            if installsAutomatically != oldValue {
                actions.setInstallsAutomatically(installsAutomatically)
            }
        }
    }
    /// The download can be cancelled until Sparkle starts unpacking it.
    var canCancel = true
    @ObservationIgnored var actions = Actions()

    var version: String {
        offer?.versions.new ?? ""
    }

    var title: String {
        switch phase {
        case .checking:
            String(localized: "Checking for updates…")
        case .offer:
            offer.map(UpdateWindowLabel.offerTitle) ?? ""
        case .downloading, .preparing:
            UpdateWindowLabel.downloadingTitle(version: version)
        case .ready:
            UpdateWindowLabel.readyTitle(version: version)
        case .installing:
            UpdateWindowLabel.installingTitle(version: version)
        case .installedWhileRunning(let version):
            UpdateWindowLabel.installedTitle(version: version)
        }
    }

    /// Closing the window, or Esc, does what `UpdatePhase.closing` says.
    func close() {
        switch phase.closing {
        case .cancel:
            if canCancel {
                actions.cancel()
            }
        case .remindLater:
            actions.remindLater()
        case .hide:
            actions.hide()
        case .installOnQuit:
            actions.installOnQuit()
        case .later:
            actions.later()
        case .refuse:
            NSSound.beep()
        }
    }

    func receive(_ length: UInt64) {
        let now = Date.now
        download.receive(length, at: now)
        secondsLeft = download.secondsLeft(now: now)
    }
}

/// Warble's own Software Update window, in place of Sparkle's: a borderless card, as Shot's is, drawn with the system's
/// colours, fonts and controls. It floats on top, drags from anywhere outside its controls, and fits its content as the
/// update moves from the check to the offer, the download and the relaunch.
final class UpdateWindow: NSWindow {
    let model: UpdateWindowModel
    private var shownOnce = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(model: UpdateWindowModel) {
        self.model = model
        let width = model.phase.width
        let height = NSView.fittingHeight(of: UpdateView(model: model), width: width)
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        title = String(localized: "Software Update")
        setAccessibilitySubrole(.dialog)
        // Floating, so an update offered while you work opens on top of other windows, other apps' included, even while
        // Warble isn't the active app. The menu still offers it again.
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // The card draws its own rounded background, and the shadow follows it.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let content = UpdateView(model: model)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                // After SwiftUI's layout pass, never inside it: resizing the window from there throws.
                DispatchQueue.main.async { self?.fit(size) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        contentView = NSView(hosting: content)
    }

    /// Esc, and ⌘W from the app menu, do what the state's Later or Cancel does, so closing never leaves Sparkle waiting.
    override func cancelOperation(_ sender: Any?) {
        model.close()
    }

    override func performClose(_ sender: Any?) {
        model.close()
    }

    /// Brings the window forward. The first time, it's centred on the screen with the pointer and rises a few points as
    /// it fades in, or only fades with Reduce Motion. It takes a Dock icon while it's open, as Settings does.
    func present(activating: Bool) {
        DockIcon.show(for: .update)
        if shownOnce {
            bringForward(activating: activating)
        } else {
            shownOnce = true
            arrive(activating: activating)
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: model.title, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    private func bringForward(activating: Bool) {
        if activating {
            NSApp.activate()
            makeKeyAndOrderFront(nil)
            // Activation is cooperative, so it can be refused right after the Dock icon appears; raise the window anyway
            // and ask again once the policy has settled.
            orderFrontRegardless()
            DispatchQueue.main.async {
                NSApp.activate()
            }
        } else {
            // On top, other apps' windows included, without making Warble active or the window key.
            orderFrontRegardless()
        }
    }

    private func arrive(activating: Bool) {
        // Let the content take its height first, so the frame below has it.
        contentView?.layoutSubtreeIfNeeded()
        let resting = centred(frame.size)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        alphaValue = 0
        setFrame(reduced ? resting : resting.offsetBy(dx: 0, dy: -Native.windowRise), display: true)
        bringForward(activating: activating)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? Native.windowFade : Native.windowArrive
            context.timingFunction = reduced ? CAMediaTimingFunction(name: .easeOut) : Native.windowArriveCurve
            animator().alphaValue = 1
            // Only the origin moves, so a height the content asks for meanwhile isn't undone.
            if !reduced {
                animator().setFrameOrigin(resting.origin)
            }
        }
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        DockIcon.hide(for: .update)
    }

    private func centred(_ size: NSSize) -> NSRect {
        let pointer = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSRect(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// Takes the size the content needs, keeping the top edge and the middle where they are, so the buttons swapping
    /// for a progress bar never makes the title jump.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard wanted.width > 0, wanted.height > 0, wanted != frame.size else {
            return
        }
        let resting = shownOnce ? frame : centred(frame.size)
        setFrame(NSRect(x: (resting.midX - wanted.width / 2).rounded(), y: resting.maxY - wanted.height, width: wanted.width, height: wanted.height), display: true)
        invalidateShadow()
    }
}

/// The window's content: the offer with its release notes, or one of the short states with a smaller icon, on a
/// rounded card of the window background with a hairline edge.
struct UpdateView: View {
    @Bindable var model: UpdateWindowModel
    @Environment(\.colorSchemeContrast) private var contrast

    static let radius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius)
        let increased = contrast == .increased
        Group {
            if model.phase == .offer, let offer = model.offer {
                OfferView(model: model, offer: offer)
            } else {
                StepView(model: model)
            }
        }
        .frame(width: model.phase.width)
        // The card has no title bar, so a drag anywhere outside the controls moves it. SwiftUI gestures, not an AppKit
        // view, so the buttons and anything selectable keep their own clicks and drags. This one covers the icon and
        // headings, which sit in front of the background below and would otherwise take the drag.
        .gesture(WindowDragGesture())
        // The gaps between them, with no content shape above, reach this one.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                // The first click on the window while it's in the background drags it too.
                .allowsWindowActivationEvents(true)
        }
        .background(Color(nsColor: .windowBackgroundColor), in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(increased ? Color.primary.opacity(0.6) : Color(nsColor: .separatorColor), lineWidth: increased ? 1 : 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: model.title))
    }
}

/// The yellow default button.
private struct DefaultButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .yellowDefaultButton()
    }
}

private struct OfferView: View {
    @Bindable var model: UpdateWindowModel
    let offer: UpdateOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                AppIcon(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: UpdateWindowLabel.offerTitle(offer))
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: UpdateWindowLabel.offerMessage(offer))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            if !model.notes.isEmpty {
                NotesBand(notes: model.notes, version: offer.versions.new)
            }
            VStack(alignment: .leading, spacing: 14) {
                if model.buttons?.showsAutomaticInstall == true {
                    Toggle("Install updates automatically from now on", isOn: $model.installsAutomatically)
                        .toggleStyle(.checkbox)
                        .help(String(localized: "New versions download by themselves and install the next time Warble quits. You can turn this off in Settings › About."))
                }
                buttons
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    /// Skip This Version on the left, then Remind Me Tomorrow and Install and Relaunch. When a long translation leaves
    /// no room, Skip moves under the other two, and when even those two don't fit side by side, the three stack with the
    /// default button on top, as a stacked alert's buttons do.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                skip
                Spacer(minLength: 8)
                later
                install
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    later
                    install
                }
                skip
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 8) {
                install
                later
                skip
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private var skip: some View {
        if model.buttons?.showsSkip == true {
            Button("Skip This Version") { model.actions.skip() }
                .fixedSize()
                .help(String(localized: "Don't offer this version again. A newer one is still offered."))
        }
    }

    @ViewBuilder private var later: some View {
        switch model.buttons?.later {
        case .remindTomorrow:
            Button("Remind Me Tomorrow") { model.actions.remindLater() }
                .fixedSize()
                .help(String(localized: "Offer this version again at tomorrow's check"))
        case .installOnQuit:
            Button("Install on Quit") { model.actions.remindLater() }
                .fixedSize()
                .help(String(localized: "Install the new version the next time Warble quits"))
        case .hidden, nil:
            EmptyView()
        }
    }

    @ViewBuilder private var install: some View {
        if model.buttons?.install == .learnMore {
            DefaultButton("Learn More…") { model.actions.install() }
                .fixedSize()
                .help(String(localized: "Read about this version on the web"))
        } else {
            DefaultButton("Install and Relaunch") { model.actions.install() }
                .fixedSize()
                .help(String(localized: "Download the new version, then quit Warble, install it and open it again"))
        }
    }
}

/// The release notes on a lightly filled band between hairlines, across the card: each version since the
/// installed one, newest first, with its groups and changes. It takes the list's height, and only a long list stops at
/// 230 points and scrolls, since a scroll view has no height of its own to give the card.
private struct NotesBand: View {
    let notes: ReleaseNotes
    let version: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let list = VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(notes.versions.enumerated()), id: \.offset) { _, release in
                VStack(alignment: .leading, spacing: 10) {
                    if notes.showsVersions, let version = release.version {
                        Text(verbatim: version)
                            .font(.system(size: 13, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(Array(release.groups.enumerated()), id: \.offset) { _, group in
                        GroupList(group: group)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)

        Group {
            if notes.scrolls {
                ScrollView { list }
                    .frame(height: 230)
            } else {
                list
            }
        }
        .background { Rectangle().fill(Color(nsColor: .quaternarySystemFill)) }
        .overlay(alignment: .top) { divider }
        .overlay(alignment: .bottom) { divider }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: UpdateWindowLabel.notesName(version: version)))
    }

    private var divider: some View {
        Rectangle()
            .fill(contrast == .increased ? Color.primary.opacity(0.6) : Color(nsColor: .separatorColor))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

private struct GroupList: View {
    let group: ReleaseNotes.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let heading = group.kind.label {
                Text(verbatim: heading)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(verbatim: "•")
                        .accessibilityHidden(true)
                    Text(verbatim: item)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.leading, 4)
            }
        }
        .lineSpacing(2)
    }
}

/// Checking, downloading, ready, installing and installed: the smaller icon beside a title, a line or a progress bar,
/// and the buttons on the right.
private struct StepView: View {
    let model: UpdateWindowModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AppIcon(size: 44)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if model.phase == .checking || model.phase == .installing {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: model.title)
                        .font(.system(size: 14, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.top, 2)
                detail
                buttons
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(20)
    }

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .downloading:
            progress(model.download.fraction, leading: UpdateWindowLabel.downloaded(model.download), trailing: model.secondsLeft.map(UpdateWindowLabel.timeLeft))
        case .preparing(let fraction):
            progress(fraction, leading: String(localized: "Getting it ready to install…"), trailing: nil)
        case .ready, .installing:
            Text("Warble quits and reopens to finish. Your music keeps playing.")
                .fixedSize(horizontal: false, vertical: true)
        case .installedWhileRunning:
            Text("It was installed while this copy was running. Relaunch to start using it.")
                .fixedSize(horizontal: false, vertical: true)
        case .checking, .offer:
            EmptyView()
        }
    }

    private func progress(_ fraction: Double?, leading: String, trailing: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(Color(nsColor: .systemGray))
            .accessibilityLabel(Text(verbatim: model.title))
            .accessibilityValue(Text(verbatim: [leading, trailing].compactMap(\.self).joined(separator: ", ")))
            HStack {
                Text(verbatim: leading)
                Spacer(minLength: 8)
                if let trailing {
                    Text(verbatim: trailing)
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch model.phase {
        case .checking, .downloading, .preparing:
            Button("Cancel") { model.actions.cancel() }
                .disabled(!model.canCancel)
        case .ready:
            HStack(spacing: 8) {
                Button("Later") { model.actions.installOnQuit() }
                    .help(String(localized: "Install the new version the next time Warble quits"))
                DefaultButton("Relaunch Now") { model.actions.relaunch() }
            }
        case .installedWhileRunning:
            HStack(spacing: 8) {
                Button("Later") { model.actions.later() }
                DefaultButton("Relaunch") { model.actions.relaunch() }
            }
        case .offer, .installing:
            EmptyView()
        }
    }
}

/// Warble's icon, which VoiceOver skips since the title names the app.
private struct AppIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
