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
        case .ready, .installing:
            UpdateWindowLabel.readyTitle(version: version)
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

/// Warble's own Software Update window, in place of Sparkle's: a standard window with only the close button, which fits
/// its content as the update moves from the check to the offer, the download and the relaunch.
final class UpdateWindow: NSWindow, NSWindowDelegate {
    let model: UpdateWindowModel
    private var shownOnce = false

    init(model: UpdateWindowModel) {
        self.model = model
        let width = model.phase.width
        let height = NSView.fittingHeight(of: UpdateView(model: model), width: width)
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = String(localized: "Software Update")
        // A normal level, like Sparkle's window: an update offered while you work can sit behind other windows, and the
        // menu offers it again.
        level = .normal
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        delegate = self
        let content = UpdateView(model: model)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in
                // After SwiftUI's layout pass, never inside it: resizing the window from there throws.
                DispatchQueue.main.async { self?.fit(size) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        contentView = NSView(hosting: content)
    }

    /// The close button does what the state's Later or Cancel does, so closing never leaves Sparkle waiting.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.close()
        return false
    }

    override func cancelOperation(_ sender: Any?) {
        model.close()
    }

    /// Brings the window forward. The first time, it's centred, as standard windows open. It takes a Dock icon while
    /// it's open, as Settings does.
    func present(activating: Bool) {
        DockIcon.show(for: .update)
        if !shownOnce {
            shownOnce = true
            center()
        }
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
            orderFront(nil)
        }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: model.title, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// Puts the window behind the others, for an update a scheduled check found while you were busy in another of
    /// Warble's windows.
    func presentBehind() {
        DockIcon.show(for: .update)
        if !shownOnce {
            shownOnce = true
            center()
        }
        orderBack(nil)
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        DockIcon.hide(for: .update)
    }

    /// Takes the size the content needs, keeping the top edge and the middle where they are, so the buttons swapping
    /// for a progress bar never makes the title jump.
    private func fit(_ size: CGSize) {
        let wanted = NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        let current = contentRect(forFrameRect: frame).size
        guard wanted.width > 0, wanted.height > 0, wanted != current else {
            return
        }
        var next = frameRect(forContentRect: NSRect(origin: .zero, size: wanted))
        next.origin = NSPoint(x: (frame.midX - next.width / 2).rounded(), y: frame.maxY - next.height)
        setFrame(next, display: true)
    }
}

/// The window's content: the offer with its release notes, or one of the short states with a smaller icon.
struct UpdateView: View {
    @Bindable var model: UpdateWindowModel

    var body: some View {
        Group {
            if model.phase == .offer, let offer = model.offer {
                OfferView(model: model, offer: offer)
            } else {
                StepView(model: model)
            }
        }
        .frame(width: model.phase.width)
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
        VStack(alignment: .leading, spacing: 14) {
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
            if !model.notes.isEmpty {
                NotesBox(notes: model.notes, version: offer.versions.new)
            }
            if model.buttons?.showsAutomaticInstall == true {
                Toggle("Install updates automatically from now on", isOn: $model.installsAutomatically)
                    .toggleStyle(.checkbox)
                    .help(String(localized: "New versions download by themselves and install the next time Warble quits. You can turn this off in Settings › About."))
            }
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 20)
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

/// The release notes in a 230 pt box that scrolls, as a text view sits in a window: each version since the installed
/// one, newest first, with its groups and changes.
private struct NotesBox: View {
    let notes: ReleaseNotes
    let version: String

    var body: some View {
        let showsVersions = notes.versions.count > 1
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(notes.versions.enumerated()), id: \.offset) { _, release in
                    VStack(alignment: .leading, spacing: 10) {
                        if showsVersions, let version = release.version {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 230)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: UpdateWindowLabel.notesName(version: version)))
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

/// Checking, downloading, ready and installed: the smaller icon beside a title, a line or a progress bar, and the
/// buttons on the right.
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
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 18)
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
        case .ready, .installing:
            HStack(spacing: 8) {
                Button("Later") { model.actions.installOnQuit() }
                    .help(String(localized: "Install the new version the next time Warble quits"))
                DefaultButton("Relaunch Now") { model.actions.relaunch() }
            }
            .disabled(model.phase == .installing)
        case .installedWhileRunning:
            HStack(spacing: 8) {
                Button("Later") { model.actions.later() }
                DefaultButton("Relaunch") { model.actions.relaunch() }
            }
        case .offer:
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
