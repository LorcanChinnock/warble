import AppKit
import Observation
import os
import Sparkle
import WarbleModel

private let log = Logger.warble("update")

/// Wraps Sparkle. Nothing goes over the network until the user agrees: Sparkle asks once whether to
/// check automatically (Info.plist leaves SUEnableAutomaticChecks unset), and "Check for Updates…" is always manual.
/// Local builds have an empty SUFeedURL, so the updater never starts and Sparkle can't replace them with a release.
/// Homebrew or a drag-and-drop can replace the app while it runs, so before offering an update it checks the
/// copy on disk and offers a relaunch instead.
@MainActor
@Observable
final class Updater: NSObject {
    /// Set while a scheduled check has found an update the user hasn't looked at yet. A menu bar app's
    /// update alert can open behind other windows, so the menu offers it too.
    private(set) var pendingVersion: String?
    private(set) var canCheckForUpdates = false
    /// Set from the moment Sparkle starts a check, scheduled or asked for, until it finds an update or nothing or fails.
    private(set) var isChecking = false
    /// What the last check in this session found, for Settings' status. Nil until one finishes.
    private(set) var lastCheckResult: UpdateCheckResult?
    /// When Sparkle last checked, in this session or an earlier one. Sparkle stores it.
    private(set) var lastCheckDate: Date?
    /// Whether this build has a feed, which only `make dist` gives it, so the updater runs at all.
    let isEnabled = !((Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "").isEmpty

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastCheckObservation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: isEnabled, updaterDelegate: self, userDriverDelegate: self)
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
        lastCheckObservation = controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.lastCheckDate = self.controller.updater.lastUpdateCheckDate
            }
        }
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
            log.notice("Automatic update checks \(newValue ? "on" : "off")")
        }
    }

    /// Sparkle's automatic downloads: a found update downloads by itself and installs when Warble quits.
    var automaticallyDownloads: Bool {
        get {
            access(keyPath: \.automaticallyDownloads)
            return controller.updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyDownloads) {
                controller.updater.automaticallyDownloadsUpdates = newValue
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

    /// What About's two switches show.
    var switches: UpdateSwitches {
        UpdateSwitches(hasFeed: isEnabled, checksAutomatically: automaticallyChecks, downloadsAutomatically: automaticallyDownloads)
    }

    #if DEBUG
    /// `-updateStatusPreview checking|ready|upToDate|lastChecked|failed|off` shows that status line in a dev build, which
    /// has no feed and so would only ever show `off`.
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
        controller.checkForUpdates(nil)
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

    /// No update found and a cancelled install both arrive here too, and aren't failures. Our own relaunch offer below
    /// cancels with `installationCanceledError`.
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
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Self.offerRelaunch(installed: installed)
            }
        }
        throw NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))
    }

    private static func offerRelaunch(installed: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Warble \(installed) is installed")
        alert.informativeText = String(localized: "It was installed while Warble was running. Relaunch to use it.")
        alert.addButton(withTitle: String(localized: "Relaunch"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
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

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            log.notice("Update \(version) available")
            if !userInitiated {
                pendingVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            pendingVersion = nil
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            pendingVersion = nil
        }
    }
}
