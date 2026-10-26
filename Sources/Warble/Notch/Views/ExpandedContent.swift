import AppKit
import Carbon.HIToolbox
import SwiftUI
import WarbleCore

/// The full card: art, title, artist and album, then the position and the controls.
struct ExpandedContent: View {
    let playback: PlaybackState
    let artwork: NSImage?
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: model.player.openApp) {
                    Artwork(image: artwork)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.notch)
                .accessibilityLabel(model.player.appName.map { Text("Open \($0)") } ?? Text("Open the app that's playing"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Group {
                        if let artist = playback.artist { Text(artist) }
                        if let album = playback.album { Text(album) }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Native.secondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nowPlaying(playback))
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(playback.album.map { Text("From \($0)") } ?? Text(verbatim: ""))
                // VoiceOver starts here when the notch opens from the keyboard, ahead of the art beside it.
                .accessibilitySortPriority(1)
                Spacer(minLength: 0)
                if model.doctor.needsAttention {
                    Button { model.onShowDoctor(true) } label: {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Native.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.notch)
                    .accessibilityLabel("Show what's wrong")
                }
            }
            Spacer(minLength: 0)
            SourceChips(chips: model.player.chips, follow: model.player.follow)
            Scrubber(playback: playback) { model.player.send(.seek(to: $0)) }
            Spacer(minLength: 0)
            PlaybackControls(playback: playback, skipsBySeconds: model.skipsBySeconds, send: model.player.send, skip: model.player.skip)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let volume = model.player.volume {
                    VolumeSlider(volume: model.player.isMuted ? 0 : volume, isMuted: model.player.isMuted, set: model.player.setVolume)
                } else {
                    Spacer(minLength: 0)
                }
                OutputButton(model: model)
                    .frame(width: 34, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
