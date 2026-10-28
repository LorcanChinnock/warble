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

/// A soft white wash over a view while the pointer is on it, so the notch answers the pointer before a click. It's drawn
/// over the content rather than behind it, which works on art too, and it eases in and out unless Reduce Motion is on.
private struct HoverWash<S: Shape>: ViewModifier {
    let shape: S
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay { shape.fill(.white.opacity(hovering ? 0.14 : 0)).allowsHitTesting(false) }
            .onHover { inside in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { hovering = inside }
            }
    }
}

extension View {
    /// A faint white wash in `shape` while the pointer is over this view.
    func hoverWash<S: Shape>(_ shape: S) -> some View {
        modifier(HoverWash(shape: shape))
    }
}
