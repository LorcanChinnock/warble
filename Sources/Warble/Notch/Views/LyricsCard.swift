import SwiftUI
import WarbleCore

/// The lyrics card the player's lyrics button opens, the player's size: the line being sung in white, with the line
/// before it and the three after in grey, and the lyrics button where the player has it, to swap back. It draws the lines
/// it's given; each keeps its row as the song moves on, so the lines slide up.
struct LyricsCard: View {
    let lyrics: LyricsExcerpt
    let model: NotchModel

    /// Room for each line, so the line being sung stays put near the start of the song.
    private static let rowHeight: CGFloat = 22

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lyrics.rows) { row in
                    Text(verbatim: row.text)
                        .font(.system(size: row.isCurrent ? 15 : 13, weight: row.isCurrent ? .semibold : .regular))
                        .foregroundStyle(row.isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(Native.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: Self.rowHeight)
                        .transition(.opacity)
                }
            }
            .padding(.top, CGFloat(lyrics.missingBefore) * Self.rowHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Lyrics"))
            .accessibilityValue(Text(verbatim: lyrics.rows.first(where: \.isCurrent)?.text ?? ""))
            .accessibilityAddTraits(.updatesFrequently)
            // VoiceOver starts on the lines when the notch opens from the keyboard, ahead of the button below them.
            .accessibilitySortPriority(1)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LyricsButton(isOn: true) { model.onShowLyrics(false) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

/// Swaps the open card between the player and the lyrics, in the same place on both. Like shuffle and repeat, it's grey
/// when off and white with a dot under it when on, so it doesn't say which card shows by colour alone.
struct LyricsButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(Native.secondary))
                // As wide as Repeat above it, so the two share a column.
                .frame(width: 30, height: 24)
                .overlay(alignment: .bottom) {
                    if isOn {
                        Circle().fill(.white)
                            .frame(width: 3, height: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.notch)
        .accessibilityLabel(isOn ? Text("Show the player") : Text("Show lyrics"))
    }
}
