import AppKit
import SwiftUI
import WarbleCore

extension NSView {
    /// A window's content view hosting SwiftUI one level down. A hosting view that is itself the content view resizes the
    /// window and sets its size limits from inside AppKit's layout pass, which throws once content changes under a visible window.
    /// `settings` is what every `@Setting` inside reads.
    convenience init(hosting rootView: some View, settings: SettingsStore) {
        self.init()
        let hosting = NSHostingView(rootView: rootView.modifier(TextSizeRoot()).environment(settings))
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }
}

/// Hands Settings › General › Text size to everything a hosting view shows.
private struct TextSizeRoot: ViewModifier {
    @Setting(PreferenceKey.textSize) private var textSize: TextSize

    func body(content: Content) -> some View {
        content.environment(\.textSize, textSize)
    }
}
