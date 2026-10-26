import AppKit
import SwiftUI
import WarbleCore

/// The displays connected now, kept up to date.
@MainActor
final class Displays: DisplayProvider {
    private(set) var displays: [NotchDisplay] = []
    private var observer: NSObjectProtocol?
    var onChange: () -> Void = {}

    init() {
        read()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.read()
                self?.onChange()
            }
        }
    }

    private func read() {
        displays = NSScreen.notchDisplays
    }
}
