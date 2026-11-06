import Foundation

/// Carries out the effects that go through a port, and hands the rest, which need AppKit, to `platform`.
@MainActor
public final class EffectRunner {
    private let hotkeys: any HotkeyRegistrar
    private let volume: any VolumeControl
    private let outputs: any AudioOutputs
    private let favourites: any MusicFavourites
    /// Carries out the effects that need AppKit. The app sets it, since it owns what they change.
    public var platform: (AppEffect) -> Void = { _ in }
    /// Where an answer goes back in as an action. The store sets it once both exist.
    public var dispatch: (AppAction) -> Void = { _ in }
    /// The app that's playing reports through it and takes commands, or `nil` before one starts.
    public var source: (any NowPlayingSource)?
    /// Whether Escape is Warble's now, so it's taken once and let go of only when held.
    private var holdsEscape = false
    private var followsVolume = false

    public init(hotkeys: any HotkeyRegistrar, volume: any VolumeControl, outputs: any AudioOutputs, favourites: any MusicFavourites) {
        self.hotkeys = hotkeys
        self.volume = volume
        self.outputs = outputs
        self.favourites = favourites
    }

    public func perform(_ effect: AppEffect) {
        switch effect {
        case .takeEscape(true):
            guard !holdsEscape else { return }
            holdsEscape = hotkeys.registerTemporary(.escape, for: .notch) { [weak self] in
                self?.dispatch(.dismiss(except: nil))
            }
        case .takeEscape(false):
            guard holdsEscape else { return }
            hotkeys.unregisterTemporary(for: .notch)
            holdsEscape = false
        case .followVolume(let follow):
            followVolume(follow)
        case .setVolume(let value):
            volume.set(value)
            readVolume()
        case .setMuted(let muted):
            volume.setMuted(muted)
            readVolume()
        case .selectOutput(let id):
            // The volume's listener follows the new output, and reads its volume.
            outputs.select(id)
            readOutputs()
        case .send(let command):
            guard let source else { return }
            Task { await source.send(command) }
        case .readFavourite(let ask):
            // Off the main actor, after the card has opened, so Music being slow never holds up the notch.
            let favourites = favourites
            Task { [weak self] in
                let value = await favourites.isFavourite(title: ask.track.title)
                self?.dispatch(.favouriteAnswered(value, ask))
            }
        case .setFavourite(let favourited, let ask):
            let favourites = favourites
            Task { [weak self] in
                let value = await favourites.setFavourite(favourited, title: ask.track.title)
                self?.dispatch(.favouriteAnswered(value, ask))
            }
        case .watchClicksOutside, .openApp, .openArtist, .haptic:
            platform(effect)
        }
    }

    /// Reads the volume and the outputs, and follows changes from the volume keys and elsewhere, only while the slider
    /// shows.
    private func followVolume(_ follow: Bool) {
        guard follow != followsVolume else { return }
        followsVolume = follow
        if follow {
            readVolume()
            readOutputs()
            volume.startListening { [weak self] in self?.readVolume() }
            outputs.startListening { [weak self] in self?.readOutputs() }
        } else {
            volume.stopListening()
            outputs.stopListening()
        }
    }

    private func readVolume() {
        dispatch(.volumeRead(volume.volume, isMuted: volume.isMuted))
    }

    private func readOutputs() {
        dispatch(.outputsRead(outputs.all, current: outputs.current))
    }
}

extension KeyCombo {
    /// Escape with no modifiers.
    public static let escape = KeyCombo(keyCode: 53, modifiers: 0)
}
