import AppKit
import os
import Sparkle
import WarbleCore
import WarbleModel

private let log = Logger.warble("update")

/// Sparkle's user interface for Warble, ported from Shot's. `UpdateWindow` draws the check you asked for, the offer, the
/// download and the relaunch, in place of Sparkle's standard windows. Sparkle's own alerts still show its first-run
/// question (whether to check automatically), "You're up to date", errors and "installed", through a standard driver
/// this one hands those to.
///
/// Every choice means what it meant in Sparkle's window: Skip This Version never offers that version again, Remind Me
/// Tomorrow asks at the next scheduled check, closing the offer is Remind Me Tomorrow, and a critical update can't be put
/// off. Closing the window while it downloads only hides it.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    private let standard: SPUStandardUserDriver
    private weak var owner: Updater?
    weak var updater: SPUUpdater?

    let model = UpdateWindowModel()
    private var window: UpdateWindow?
    private var item: SUAppcastItem?

    private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    private var receivedAttention = false
    private var opportuneTime = ContinuousClock.now
    private var observers: [NSObjectProtocol] = []

    init(owner: Updater, standardDelegate: SPUStandardUserDriverDelegate) {
        self.owner = owner
        standard = SPUStandardUserDriver(hostBundle: .main, delegate: standardDelegate)
        super.init()
        model.actions = UpdateWindowModel.Actions(
            install: { [weak self] in self?.install() },
            remindLater: { [weak self] in self?.choose(.dismiss) },
            skip: { [weak self] in self?.choose(.skip) },
            cancel: { [weak self] in self?.cancel() },
            hide: { [weak self] in self?.window?.orderOut(nil) },
            relaunch: { [weak self] in self?.relaunch() },
            installOnQuit: { [weak self] in self?.installOnQuit() },
            later: { [weak self] in self?.closeWindow() },
            // Sparkle's checkbox changed the setting at once, before any button, and so does this one.
            setInstallsAutomatically: { [weak owner] on in owner?.automaticallyDownloads = on }
        )
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteAttention() }
        })
        // noteAttention checks that it's the update window that became key.
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteAttention() }
        })
    }

    /// Whether a check you asked for is running and can be stopped, for About's Cancel.
    var canCancelCheck: Bool {
        model.phase == .checking && cancellation != nil && window != nil
    }

    // MARK: Asking first

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    // MARK: Checking

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        model.offer = nil
        model.buttons = nil
        model.canCancel = true
        model.phase = .checking
        promptWindow().present(activating: true)
        owner?.checkWindowChanged()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        item = appcastItem
        choiceReply = reply
        cancellation = nil
        receivedAttention = false
        let offer = Self.offer(appcastItem, state: state)
        model.offer = offer
        model.notes = Self.notes(appcastItem.itemDescription, format: ReleaseNotes.format(sparkle: appcastItem.itemDescriptionFormat), installed: offer.installedVersion)
        model.buttons = UpdateOfferButtons(
            offer: offer,
            automaticallyChecks: updater?.automaticallyChecksForUpdates ?? false,
            allowsAutomaticUpdates: updater?.allowsAutomaticUpdates ?? false
        )
        model.installsAutomatically = updater?.automaticallyDownloadsUpdates ?? false
        model.phase = .offer
        log.notice("Update \(appcastItem.displayVersionString) available")
        owner?.updateShown(version: appcastItem.displayVersionString, userInitiated: state.userInitiated)
        owner?.checkWindowChanged()
        if state.userInitiated {
            promptWindow().present(activating: true)
        } else {
            showScheduled()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard model.notes.isEmpty, let installed = model.offer?.installedVersion else {
            return
        }
        let encoding = downloadData.textEncodingName
            .map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
            .flatMap { $0 == kCFStringEncodingInvalidId ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding($0)) } ?? .utf8
        let format = ReleaseNotes.format(mimeType: downloadData.mimeType, pathExtension: downloadData.url.pathExtension)
        model.notes = Self.notes(String(data: downloadData.data, encoding: encoding), format: format, installed: installed)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        log.error("Release notes didn't download: \(error.localizedDescription, privacy: .public)")
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        closeWindow()
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        closeWindow()
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    // MARK: Downloading and installing

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        model.download = UpdateDownloadProgress()
        model.secondsLeft = nil
        model.canCancel = true
        model.phase = .downloading
        showIfHidden()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        model.download.expect(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        model.receive(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        model.canCancel = false
        model.phase = .preparing(0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.phase = .preparing(progress)
    }

    /// The download is ready. The window says so, even if it was closed while downloading, and Relaunch Now installs it.
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = reply
        model.phase = .ready
        promptWindow().present(activating: false)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if applicationTerminated {
            model.phase = .installing
            return
        }
        // Warble didn't quit. Sparkle installs when Warble next quits, and Check for Updates… offers the relaunch again.
        retryTermination = retryTerminatingApplication
        closeWindow()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        closeWindow()
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func showUpdateInFocus() {
        if let window, window.isVisible {
            window.present(activating: true)
        } else if window != nil {
            // Closed while downloading: Check for Updates… brings it back.
            promptWindow().present(activating: true)
        } else if retryTermination != nil {
            model.phase = .ready
            promptWindow().present(activating: true)
        } else {
            standard.showUpdateInFocus()
        }
    }

    func dismissUpdateInstallation() {
        choiceReply = nil
        cancellation = nil
        installReply = nil
        retryTermination = nil
        receivedAttention = false
        item = nil
        // Sparkle ends the session right after `Updater` stops it to offer a relaunch, so that offer stays.
        if case .installedWhileRunning = model.phase {} else {
            closeWindow()
        }
        standard.dismissUpdateInstallation()
        owner?.updateSessionEnded()
    }

    // MARK: Installed while running

    /// Another installer replaced Warble while it ran: the window offers a relaunch, as the alert it replaces did.
    func showInstalledWhileRunning(version: String, userInitiated: Bool) {
        cancellation = nil
        model.phase = .installedWhileRunning(version: version)
        owner?.checkWindowChanged()
        if userInitiated {
            promptWindow().present(activating: true)
        } else {
            showScheduled()
        }
    }

    // MARK: Gentle reminders

    /// Sparkle calls this, when it's there, at launch and after each check it schedules, so an update found within 3
    /// seconds can take the keyboard.
    @objc func resetTimeSinceOpportuneUpdateNotice() {
        opportuneTime = .now
    }

    /// Sparkle warns a background app that has no gentle reminders. Warble has one: the menu's "Update to …" item.
    @objc func logGentleScheduledUpdateReminderWarningIfNeeded() {}

    /// Shows what a scheduled check found, as Sparkle's standard driver does for a menu bar app. Near launch it takes the
    /// keyboard. Otherwise it appears without taking the keyboard from another app, and behind Warble's own windows while
    /// you're using one, and the menu offers it until you look at it.
    private func showScheduled() {
        let nearLaunch = ContinuousClock.now - opportuneTime <= .seconds(3)
        let window = promptWindow()
        if nearLaunch {
            window.present(activating: true)
        } else if NSApp.isActive, NSApp.keyWindow != nil {
            window.presentBehind()
        } else {
            window.present(activating: false)
        }
    }

    /// The person has seen the offer once its window is key while Warble is active, as Sparkle's standard driver judges it.
    private func noteAttention() {
        guard !receivedAttention, model.phase == .offer, let window, window.isKeyWindow, NSApp.isActive else {
            return
        }
        receivedAttention = true
        owner?.updateGotAttention()
    }

    // MARK: Choices

    private func install() {
        guard let offer = model.offer else {
            return
        }
        if offer.isInformationOnly {
            if let url = item?.infoURL {
                NSWorkspace.shared.open(url)
            }
            choose(.dismiss)
            return
        }
        switch offer.stage {
        case .notDownloaded:
            model.download = UpdateDownloadProgress()
            model.secondsLeft = nil
            // Sparkle hands over the download's Cancel once it starts.
            model.canCancel = false
            model.phase = .downloading
        case .downloaded:
            model.canCancel = false
            model.phase = .preparing(0)
        case .installing:
            model.phase = .installing
        }
        reply(.install)
    }

    private func choose(_ choice: SPUUserUpdateChoice) {
        reply(choice)
        closeWindow()
    }

    private func reply(_ choice: SPUUserUpdateChoice) {
        if !receivedAttention {
            receivedAttention = true
            owner?.updateGotAttention()
        }
        let reply = choiceReply
        choiceReply = nil
        reply?(choice)
    }

    private func cancel() {
        let cancellation = cancellation
        self.cancellation = nil
        cancellation?()
        closeWindow()
    }

    /// Stops the check you asked for, from About's Cancel.
    func cancelCheck() {
        guard model.phase == .checking else {
            return
        }
        cancel()
    }

    private func relaunch() {
        if case .installedWhileRunning = model.phase {
            Updater.relaunch()
            return
        }
        model.phase = .installing
        if let installReply {
            self.installReply = nil
            installReply(.install)
        } else if let retryTermination {
            retryTermination()
        }
    }

    /// Later on Ready: Sparkle installs the update the next time Warble quits.
    private func installOnQuit() {
        if let installReply {
            self.installReply = nil
            installReply(.dismiss)
        }
        closeWindow()
    }

    // MARK: The window

    private func promptWindow() -> UpdateWindow {
        if let window {
            return window
        }
        let window = UpdateWindow(model: model)
        self.window = window
        return window
    }

    private func showIfHidden() {
        if window?.isVisible != true {
            promptWindow().present(activating: false)
        }
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window = nil
        owner?.checkWindowChanged()
    }

    private static func notes(_ text: String?, format: ReleaseNotes.Format, installed: String) -> ReleaseNotes {
        guard let text else {
            return ReleaseNotes(versions: [])
        }
        return ReleaseNotes(text, format: format).since(installed)
    }

    private static func offer(_ item: SUAppcastItem, state: SPUUserUpdateState) -> UpdateOffer {
        let info = Bundle.main.infoDictionary ?? [:]
        let stage: UpdateOffer.Stage = switch state.stage {
        case .downloaded: .downloaded
        case .installing: .installing
        default: .notDownloaded
        }
        return UpdateOffer(
            version: item.displayVersionString,
            build: item.versionString,
            installedVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            installedBuild: info["CFBundleVersion"] as? String ?? "?",
            stage: stage,
            downloadSize: item.contentLength,
            isCritical: item.isCriticalUpdate,
            isMajorUpgrade: item.isMajorUpgrade,
            isInformationOnly: item.isInformationOnlyUpdate
        )
    }

    #if DEBUG
    /// `-updateWindowPreview offer|checking|downloading|ready|installed` shows the window in that state with made-up
    /// details, since a dev build has no feed. Its buttons only close it.
    func preview(_ name: String) {
        let offer = UpdateOffer(version: "0.2.0", build: "200", installedVersion: "0.1.0-beta.14", installedBuild: "114", downloadSize: 6_000_000)
        model.offer = offer
        model.buttons = UpdateOfferButtons(offer: offer, automaticallyChecks: true, allowsAutomaticUpdates: true)
        model.notes = ReleaseNotes(Self.previewNotes, format: .markdown).since(offer.installedVersion)
        let close: @MainActor () -> Void = { [weak self] in self?.closeWindow() }
        model.actions = UpdateWindowModel.Actions(
            install: close, remindLater: close, skip: close, cancel: close, hide: close, relaunch: close, installOnQuit: close, later: close
        )
        switch name {
        case "checking":
            model.phase = .checking
        case "downloading":
            model.download.expect(6_000_000)
            model.download.receive(3_200_000, at: .now.addingTimeInterval(-5))
            model.secondsLeft = 5
            model.phase = .downloading
        case "ready":
            model.phase = .ready
        case "installed":
            model.phase = .installedWhileRunning(version: "0.2.0")
        default:
            model.phase = .offer
        }
        promptWindow().present(activating: true)
    }

    private static let previewNotes = """
    ## [0.2.0](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.15...v0.2.0) (2026-11-20)

    ### Features

    * **settings:** Settings has three tabs: Notch, General and About ([#438](https://github.com/LorcanChinnock/warble/issues/438)) ([13a3dff](https://github.com/LorcanChinnock/warble/commit/13a3dff))
    * **settings:** About shows whether Warble is up to date, and when it last checked ([#441](https://github.com/LorcanChinnock/warble/issues/441)) ([fecf32f](https://github.com/LorcanChinnock/warble/commit/fecf32f))
    * **update:** Warble shows new versions in its own window, with what changed ([#430](https://github.com/LorcanChinnock/warble/issues/430))

    ### Bug Fixes

    * **menu:** the menu bar icon keeps its bars while an update waits ([#431](https://github.com/LorcanChinnock/warble/issues/431))

    ## [0.1.0-beta.15](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.14...v0.1.0-beta.15) (2026-11-12)

    ### Bug Fixes

    * **notch:** the playback bar's ends line up with the volume bar ([#397](https://github.com/LorcanChinnock/warble/issues/397))

    ## [0.1.0-beta.14](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.13...v0.1.0-beta.14) (2026-11-01)

    ### Features

    * **notch:** click the speaker to mute ([#407](https://github.com/LorcanChinnock/warble/issues/407))
    """
    #endif
}
