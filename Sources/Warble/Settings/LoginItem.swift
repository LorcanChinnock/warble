import os
import ServiceManagement

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

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
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
