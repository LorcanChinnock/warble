import SwiftUI
import WarbleCore

/// The current lyric line, in the strip below the resting wings. It draws the words it's given, so a line on its way
/// out keeps its own.
struct LyricsLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.lyricsDrop)
            .accessibilityLabel(Text("Lyrics: \(text)"))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
