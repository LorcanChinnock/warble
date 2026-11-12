import SwiftUI

extension View {
    /// The redesign's default button: the icon's yellow under dark text, the window's default action. An inactive window
    /// draws a prominent button without its fill, so the text keeps the system's colour there, or it would be black on
    /// the dark window.
    func yellowDefaultButton() -> some View {
        modifier(YellowDefaultButton())
    }
}

private struct YellowDefaultButton: ViewModifier {
    @Environment(\.controlActiveState) private var activeState

    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(Color.warbleYellow)
            .foregroundStyle(activeState == .key ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.primary))
            .keyboardShortcut(.defaultAction)
    }
}
