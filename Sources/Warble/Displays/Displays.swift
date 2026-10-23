import AppKit
import SwiftUI
import WarbleCore

/// The displays connected now, kept up to date for the menu and Settings.
@MainActor
@Observable
final class Displays: DisplayProvider {
    private(set) var all: [NotchDisplay] = []
    private(set) var names: [String: String] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored var onChange: () -> Void = {}
    var displays: [NotchDisplay] { all }

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
        all = NSScreen.notchDisplays
        names = Dictionary(NSScreen.screens.map { ($0.uuid, $0.localizedName) }, uniquingKeysWith: { first, _ in first })
    }
}

extension VirtualNotchRule {
    var label: Text {
        switch self {
        case .off: Text("Off")
        case .always: Text("Always")
        case .noNotch: Text("When There's No Notch")
        }
    }
}

extension Binding where Value == [String: String] {
    /// `display`'s rule in the stored rules, or the one it follows until it's given one.
    func virtualNotchRule(for display: NotchDisplay) -> Binding<VirtualNotchRule> {
        Binding<VirtualNotchRule> {
            wrappedValue[display.id].flatMap(VirtualNotchRule.init(rawValue:)) ?? .default(isMain: display.isMain)
        } set: {
            wrappedValue[display.id] = $0.rawValue
        }
    }
}

/// A display's `VirtualNotchRule`, for one without a camera housing, as a standard picker for the menu bar menu.
struct VirtualNotchPicker: View {
    let display: NotchDisplay
    let name: String
    @Setting(PreferenceKey.virtualNotch) private var rules: [String: String]

    var body: some View {
        Picker(name, selection: $rules.virtualNotchRule(for: display)) {
            ForEach(VirtualNotchRule.allCases, id: \.self) { rule in
                rule.label.tag(rule)
            }
        }
        .accessibilityLabel(Text(verbatim: name))
    }
}
