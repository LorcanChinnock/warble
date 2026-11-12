import AppKit
import Observation
import os
import Sparkle
import WarbleModel

private let log = Logger.warble("update")

/// Wraps Sparkle. Nothing goes over the network until the user agrees: Sparkle asks once whether to
/// check automatically (Info.plist leaves SUEnableAutomaticChecks unset), and "Check for Updates…" is always manual.
/// Local builds have an empty SUFeedURL, so the updater never starts and Sparkle can't replace them with a release.
/// Warble's own `UpdateUserDriver` draws the update window. Homebrew or a drag-and-drop can replace the app while it
/// runs, so before offering an update it checks the copy on disk and offers a relaunch instead.
@MainActor
@Observable
final class Updater: NSObject {
    /// Set while a scheduled check has found an update the user hasn't looked at yet. A menu bar app's
    /// update window can open behind other windows, so the menu offers it too.
    private(set) var pendingVersion: String?
    private(set) var canCheckForUpdates = false
    /// Set from the moment Sparkle starts a check, scheduled or asked for, until it finds an update or nothing or fails.
    private(set) var isChecking = false
    /// Whether a check you asked for is running and its window is open, so About can offer Cancel. A scheduled check
    /// can't be cancelled.
    private(set) var canCancelCheck = false
    /// What the last check in this session found, for Settings' status. Nil until one finishes.
    private(set) var lastCheckResult: UpdateCheckResult?
    /// When Sparkle last checked, in this session or an earlier one. Sparkle stores it.
    private(set) var lastCheckDate: Date?
    /// Whether this build has a feed, which only `make dist` gives it, so the updater runs at all.
    let isEnabled = !((Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "").isEmpty

    @ObservationIgnored private var updater: SPUUpdater!
    @ObservationIgnored private var driver: UpdateUserDriver!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastCheckObservation: NSKeyValueObservation?

    override init() {
        super.init()
        driver = UpdateUserDriver(owner: self, standardDelegate: self)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        driver.updater = updater
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.canCheckForUpdates = self.updater.canCheckForUpdates
            }
        }
        lastCheckObservation = updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.lastCheckDate = self.updater.lastUpdateCheckDate
            }
        }
        if isEnabled {
            start()
        }
        #if DEBUG
        // A dev build has no feed, so a waiting update is made up: the menu bar icon's dot and the menus' item.
        if UserDefaults.standard.string(forKey: "updateStatusPreview") == "ready" {
            pendingVersion = "0.2.0"
        }
        if let preview = UserDefaults.standard.string(forKey: "updateWindowPreview") {
            DispatchQueue.main.async { [driver] in driver?.preview(preview) }
        }
        #endif
    }

    /// Starts Sparkle, as `SPUStandardUpdaterController` did, with an alert if the updater can't start.
    private func start() {
        do {
            try updater.start()
        } catch {
            log.error("The updater didn't start: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                let alert = NSAlert()
                alert.messageText = String(localized: "Warble can't check for updates")
                alert.informativeText = String(localized: "The updater didn't start. Install the latest Warble from the website to get updates again.")
                alert.runModal()
            }
        }
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                updater.automaticallyChecksForUpdates = newValue
            }
            log.notice("Automatic update checks \(newValue ? "on" : "off")")
        }
    }

    /// Sparkle's automatic downloads: a found update downloads by itself and installs when Warble quits.
    var automaticallyDownloads: Bool {
        get {
            access(keyPath: \.automaticallyDownloads)
            return updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyDownloads) {
                updater.automaticallyDownloadsUpdates = newValue
            }
            log.notice("Automatic update downloads \(newValue ? "on" : "off")")
        }
    }

    /// What About's status line says.
    var status: UpdateStatus {
        #if DEBUG
        if let preview = Self.previewStatus {
            return preview
        }
        #endif
        return UpdateStatus(hasFeed: isEnabled, isChecking: isChecking, pendingVersion: pendingVersion, lastResult: lastCheckResult, lastCheck: lastCheckDate)
    }

    /// The menus' update item: Check for Updates…, a waiting update, or a download's progress. It reads the update
    /// window's model, so only the menus read it, and only while they're built; the notch's hover never does.
    var menuItem: UpdateMenuItem {
        let model = driver.model
        let phase = model.phase
        let downloading = switch phase {
        case .downloading, .preparing: true
        default: false
        }
        return UpdateMenuItem(
            pendingVersion: pendingVersion, canCheck: canCheckForUpdates, phase: downloading ? phase : nil,
            version: model.version, fraction: downloading ? model.download.fraction : nil
        )
    }

    /// What About's two switches show.
    var switches: UpdateSwitches {
        UpdateSwitches(hasFeed: isEnabled, checksAutomatically: automaticallyChecks, downloadsAutomatically: automaticallyDownloads)
    }

    #if DEBUG
    /// `-updateStatusPreview checking|ready|upToDate|lastChecked|failed|off` shows that status line in a dev build, which
    /// has no feed and so would only ever show `off`. `ready` also shows a waiting update in the menus.
    private static let previewStatus: UpdateStatus? = switch UserDefaults.standard.string(forKey: "updateStatusPreview") {
    case "checking": .checking
    case "ready": .available(version: "0.2.0")
    case "upToDate": .upToDate(checked: .now.addingTimeInterval(-3600))
    case "lastChecked": .lastChecked(.now.addingTimeInterval(-26 * 3600))
    case "failed": .failed
    case "off": .off
    default: nil
    }
    #endif

    func checkForUpdates() {
        NSApp.activate()
        updater.checkForUpdates()
    }

    /// Stops the check you asked for, as the window's Cancel does.
    func cancelCheck() {
        driver.cancelCheck()
    }

    /// The window offered a version. A scheduled check's offer can open behind other windows, so the menu offers it too.
    func updateShown(version: String, userInitiated: Bool) {
        if !userInitiated {
            pendingVersion = version
        }
    }

    /// The person looked at the offer or answered it.
    func updateGotAttention() {
        pendingVersion = nil
    }

    func updateSessionEnded() {
        pendingVersion = nil
    }

    /// The window opened, closed or changed state, which decides whether About offers Cancel.
    func checkWindowChanged() {
        let can = driver?.canCancelCheck ?? false
        if canCancelCheck != can {
            canCancelCheck = can
        }
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        MainActor.assumeIsolated {
            isChecking = true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            finishCheck(.found(version: version))
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            finishCheck(.upToDate)
        }
    }

    /// No update found and a cancelled install both arrive here too, and aren't failures. The installed-while-running
    /// offer below cancels with `installationCanceledError`.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        let failed = !(error.domain == SUSparkleErrorDomain
            && [Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)].contains(error.code))
        MainActor.assumeIsolated {
            if failed {
                log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            }
            finishCheck(failed ? .failed : nil)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        MainActor.assumeIsolated {
            finishCheck(nil)
        }
    }

    /// Ends the check, keeping the last result when `result` is nil.
    private func finishCheck(_ result: UpdateCheckResult?) {
        isChecking = false
        if let result {
            lastCheckResult = result
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let infoURL = Bundle.main.bundleURL.appending(path: "Contents/Info.plist")
        guard let installed = NSDictionary(contentsOf: infoURL)?["CFBundleShortVersionString"] as? String, installed != running else {
            return
        }
        log.notice("Warble \(installed) is installed but \(running ?? "?") is running; offering a relaunch")
        let userInitiated = updateCheck == .updates
        // After Sparkle has ended the session this throw stops, so the window's state outlasts it.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.driver.showInstalledWhileRunning(version: installed, userInitiated: userInitiated)
            }
        }
        throw NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))
    }

    /// Opens a new copy of Warble and quits this one.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            log.error("Couldn't relaunch: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't relaunch Warble")
            alert.informativeText = String(localized: "Quit Warble and open it again.")
            alert.runModal()
        }
    }
}

/// Sparkle's standard driver still shows the alerts `UpdateUserDriver` hands it, such as errors and "You're up to date",
/// and reads its delegate for them.
extension Updater: SPUStandardUserDriverDelegate {}
