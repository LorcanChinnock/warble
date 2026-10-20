import AppKit
import os
import WarbleCore

private let log = Logger.warble("doctor")

/// The Doctor's checks for every display's notch, and the "!" they put on it when one fails. It checks again only when
/// something changes: the adapter stops, a player opens or quits, macOS refuses a script, or the card opens. While the
/// adapter works every check passes without asking macOS anything, so it does no work at all.
@MainActor
@Observable
final class DoctorModel {
    private(set) var checks: [Doctor.Check]
    /// The failures the user put off with Not now, until Warble opens again or another check fails.
    private(set) var dismissed: Set<Doctor.Kind> = []
    /// Whether to draw the "!".
    var needsAttention: Bool {
        Doctor.needsAttention(checks, dismissed: dismissed)
    }

    /// The adapter as the app last saw it. Anything but `.working` starts following players opening and quitting.
    var adapter: Doctor.Adapter = .working {
        didSet {
            guard adapter != oldValue else { return }
            log.notice("Adapter is \(String(describing: self.adapter), privacy: .public)")
            followPlayers(adapter != .working)
            refresh()
        }
    }

    /// Called after `needsAttention` changes.
    @ObservationIgnored var onChange: () -> Void = {}
    /// Bumped by every refresh, so one that finishes after a later one has begun is dropped.
    @ObservationIgnored private var refreshes = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        checks = Doctor.checks(Doctor.Facts(adapter: .working, macOS: .running))
    }

    /// Gathers the facts again. While the adapter works no check needs macOS, so none of it runs.
    func refresh() {
        refreshes += 1
        let refresh = refreshes
        let adapter = adapter
        Task {
            let facts = await Doctor.facts(adapter: adapter)
            guard refresh == refreshes else { return }
            update(Doctor.checks(facts))
        }
    }

    /// Checks again only when the Automation check fails, so a player that plays after the user allowed it clears the
    /// "!" without asking macOS on every change of track.
    func refreshIfAutomationFails() {
        if checks.contains(where: { $0.kind == .automation && $0.outcome == .fail }) {
            refresh()
        }
    }

    /// Hides the "!" for what fails now.
    func notNow() {
        dismissed.formUnion(checks.filter { $0.outcome == .fail }.map(\.kind))
        onChange()
    }

    func perform(_ fix: Doctor.Fix) {
        log.notice("Fix \(String(describing: fix), privacy: .public)")
        switch fix {
        case .reinstall:
            NSWorkspace.shared.open(URL(string: "https://warble.lorcanchinnock.com/docs/get-started/")!)
        case .openAgain:
            Updater.relaunch()
        case .checkForUpdates:
            Updater.shared.checkForUpdates()
        case .openAutomationSettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        case .openPlayer(let player):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func update(_ checks: [Doctor.Check]) {
        guard checks != self.checks else { return }
        let attention = needsAttention
        // A check that passes again can fail again later, and then it needs the "!".
        dismissed.subtract(checks.filter { $0.outcome != .fail }.map(\.kind))
        self.checks = checks
        log.notice("Checks: \(checks.map { "\($0.kind.rawValue) \($0.outcome.rawValue)" }.joined(separator: ", "), privacy: .public)")
        if needsAttention != attention {
            onChange()
        }
    }

    /// Music and Spotify opening or quitting changes what macOS says about Automation, and what the fallback can follow.
    private func followPlayers(_ follow: Bool) {
        let following = !observers.isEmpty
        guard follow != following else { return }
        guard follow else {
            observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            observers = []
            return
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier.flatMap(ScriptedPlayer.init(rawValue:)) != nil else { return }
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }
}
