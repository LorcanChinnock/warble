import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The "!" that opens the notch on the Doctor's checks, in a square `size` points wide.
struct AttentionButton: View {
    let model: NotchModel
    let size: CGFloat

    var body: some View {
        Button {
            model.onShowDoctor(true)
            model.onClick()
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size / 2))
                .foregroundStyle(Native.secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.notch)
        .accessibilityLabel("Show what's wrong")
        .help("Warble can't see everything")
    }
}
