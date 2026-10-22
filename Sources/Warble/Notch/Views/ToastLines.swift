import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// A track-change toast: the new title, and the artist under it, in the strip below the resting wings.
struct ToastLines: View {
    let toast: TrackToast

    var body: some View {
        VStack(spacing: 1) {
            Text(toast.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if let artist = toast.artist {
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundStyle(Native.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: NotchLayout.toastDrop)
        .accessibilityElement(children: .combine)
    }
}
