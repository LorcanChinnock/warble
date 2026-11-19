import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore
import WarbleModel

/// A plain button that Space or Return also presses while it has the focus ring, with Keyboard navigation on. A plain
/// SwiftUI button takes the focus but not the key, which would fall through to the notch's own keys (`NotchKey`).
///
/// With `pressNudge` set it also gives the press a visual answer (see `PressFeedback`). Only the playback controls opt
/// in; the other users, the volume and favourite buttons and the Settings preview, keep the hover wash alone: the
/// preview is a picture of the notch and shouldn't react, and the small icons elsewhere gain little from a bounce.
struct NotchButtonStyle: PrimitiveButtonStyle {
    /// Nil for no press effect, otherwise how far the label slides sideways while held (0 for none, negative for left).
    var pressNudge: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) { configuration.label }
            .buttonStyle(PressFeedback(nudge: pressNudge))
            .pressedByKeyboard(configuration.trigger)
    }
}

/// Plain, or with the press effect. It only restyles the label from `isPressed`, so the action still runs on the click
/// exactly as a plain button's does.
private struct PressFeedback: ButtonStyle {
    let nudge: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && nudge != nil
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? NotchMotion.pressScale : 1)
            .offset(x: pressed && !reduceMotion ? nudge ?? 0 : 0)
            // With Reduce Motion nothing moves; the label only dims a little while held.
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(pressed ? Native.pressDown : (reduceMotion ? Native.fade : Native.pressRelease), value: pressed)
    }
}

extension PrimitiveButtonStyle where Self == NotchButtonStyle {
    static var notch: NotchButtonStyle { NotchButtonStyle(pressNudge: nil) }
    /// The notch style plus a press-down scale and, with `nudge`, a slide in the skip direction.
    static func notchPress(nudge: CGFloat = 0) -> NotchButtonStyle { NotchButtonStyle(pressNudge: nudge) }
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
