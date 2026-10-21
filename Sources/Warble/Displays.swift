import AppKit
import SwiftUI
import WarbleCore

/// The displays connected now, kept up to date for the menu and Settings.
@MainActor
@Observable
final class Displays {
    static let shared = Displays()

    private(set) var all: [NotchDisplay] = []
    private(set) var names: [String: String] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        read()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        all = NSScreen.notchDisplays
        names = Dictionary(NSScreen.screens.map { ($0.uuid, $0.localizedName) }, uniquingKeysWith: { first, _ in first })
    }
}

/// A display's `VirtualNotchRule`, for one without a camera housing. The menu bar menu and Settings both show it.
struct VirtualNotchPicker: View {
    let display: NotchDisplay
    let name: String
    @Setting(PreferenceKey.virtualNotch) private var rules: [String: String]

    var body: some View {
        Picker(name, selection: rule) {
            Text("Off").tag(VirtualNotchRule.off)
            Text("Always").tag(VirtualNotchRule.always)
            Text("When There's No Notch").tag(VirtualNotchRule.noNotch)
        }
    }

    private var rule: Binding<VirtualNotchRule> {
        Binding {
            rules[display.id].flatMap(VirtualNotchRule.init(rawValue:)) ?? .default(isMain: display.isMain)
        } set: {
            rules[display.id] = $0.rawValue
        }
    }
}
