import AppKit
import os
import WarbleCore

private let log = Logger.warble("doctor")

/// The Doctor's checks as the notch's cards draw them, kept from `AppState.doctor`, and the fixes their buttons start.
@MainActor
@Observable
final class DoctorModel {
    private(set) var checks: [Doctor.Check] = []
    /// Whether to draw the "!".
    private(set) var needsAttention = false

    @ObservationIgnored private let updater: Updater
    @ObservationIgnored private let dispatch: (AppAction) -> Void

    init(updater: Updater, dispatch: @escaping (AppAction) -> Void) {
        self.updater = updater
        self.dispatch = dispatch
    }

    func apply(_ doctor: DoctorState) {
        if doctor.checks != checks {
            checks = doctor.checks
            log.notice("Checks: \(doctor.checks.map { "\($0.kind.rawValue) \($0.outcome.rawValue)" }.joined(separator: ", "), privacy: .public)")
        }
        if doctor.needsAttention != needsAttention {
            needsAttention = doctor.needsAttention
        }
    }

    /// Hides the "!" for what fails now.
    func notNow() {
        dispatch(.notNow)
    }

    func perform(_ fix: Doctor.Fix) {
        log.notice("Fix \(String(describing: fix), privacy: .public)")
        switch fix {
        case .reinstall:
            NSWorkspace.shared.open(URL(string: "https://warble.lorcanchinnock.com/docs/get-started/")!)
        case .openAgain:
            Updater.relaunch()
        case .checkForUpdates:
            updater.checkForUpdates()
        case .openAutomationSettings:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        case .openPlayer(let player):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
