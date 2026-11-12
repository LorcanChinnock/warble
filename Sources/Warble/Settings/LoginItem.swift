import os
import ServiceManagement
import SwiftUI

private let log = Logger.warble("settings")

/// Whether Warble opens at login, as System Settings › General › Login Items has it. Nothing is stored in Warble's own
/// settings, so the toggle always matches what macOS will do, even after a change in System Settings.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status

    var isEnabled: Bool { status == .enabled }
    /// Turned off in System Settings after Warble turned it on, so only System Settings can turn it on again.
    var needsApproval: Bool { status == .requiresApproval }
    /// What the last change tried to set, when macOS refused it, so the switch can say why it didn't move. Cleared by the
    /// next change that works.
    private(set) var failedChange: Bool?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failedChange = nil
        } catch {
            failedChange = enabled
            log.error("Couldn't \(enabled ? "register" : "unregister", privacy: .public) the login item: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        if status != self.status {
            self.status = status
        }
    }
}

extension LoginItem {
    /// The line under an Open at login switch when macOS refused the last change, in place of its usual description.
    var failureDetail: Text? {
        switch failedChange {
        case true?: Text("Warble couldn't turn this on. Try again, or add Warble in System Settings › General › Login Items.")
        case false?: Text("Warble couldn't turn this off. Try again, or remove Warble in System Settings › General › Login Items.")
        case nil: nil
        }
    }
}
