import SwiftUI
import WarbleCore

/// The first-run demo's hint, in the strip below the idle notch.
struct DemoHint: View {
    var body: some View {
        Text("Hover here to see what's playing")
            .font(.scaled(12))
            .foregroundStyle(Native.secondary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.hintDrop)
    }
}
