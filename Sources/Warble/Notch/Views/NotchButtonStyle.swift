import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// A plain button that Space or Return also presses while it has the focus ring, with Keyboard navigation on. A plain
/// SwiftUI button takes the focus but not the key, which would fall through to the notch's own keys (`NotchKey`).
struct NotchButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label }
            .buttonStyle(.plain)
            .pressedByKeyboard(configuration.trigger)
    }
}

extension PrimitiveButtonStyle where Self == NotchButtonStyle {
    static var notch: NotchButtonStyle { NotchButtonStyle() }
}

extension View {
    /// Runs `action` for Space or Return while this view has the focus ring.
    func pressedByKeyboard(_ action: @escaping () -> Void) -> some View {
        onKeyPress(keys: [.space, .return]) { _ in
            action()
            return .handled
        }
    }
}
