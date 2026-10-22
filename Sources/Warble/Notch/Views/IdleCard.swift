import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// While Idle: the last track played, its art dimmed, with a button that resumes it, or a line saying nothing has
/// played yet.
struct IdleCard: View {
    let model: NotchModel

    var body: some View {
        Group {
            if let lastPlayed = model.player.lastPlayed {
                HStack(spacing: 12) {
                    Button(action: model.player.openApp) {
                        Artwork(image: model.player.lastPlayedArtwork, symbolSize: 20)
                            .frame(width: 48, height: 48)
                            .opacity(Native.dimmed)
                    }
                    .buttonStyle(.notch)
                    .accessibilityLabel(lastPlayed.appName.map { Text("Open \($0)") } ?? Text("Open the app that played it"))
                    VStack(alignment: .leading, spacing: 2) {
                        Group {
                            if let appName = lastPlayed.appName { Text("Last played · \(appName)") } else { Text("Last played") }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Native.secondary)
                        Text(lastPlayed.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if let artist = lastPlayed.artist {
                            Text(artist)
                                .font(.system(size: 13))
                                .foregroundStyle(Native.secondary)
                        }
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button { model.player.send(.togglePlayPause) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.notch)
                    .accessibilityLabel("Resume")
                }
            } else {
                VStack(spacing: 3) {
                    Text("Nothing playing")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Play something and it shows here")
                        .font(.system(size: 12))
                        .foregroundStyle(Native.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}
