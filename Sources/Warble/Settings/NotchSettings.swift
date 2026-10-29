import Foundation
import os
import WarbleModel

private let log = Logger.warble("settings")

/// What Settings chooses about the notch: whether a virtual notch shows the title in its middle, which starts off, how
/// long a paused song stays, when a virtual notch is there, whether the open card glows, which starts on, and how big the open card is, the face of the notch's title, and whether the title and bars take the album's colour, which starts off. Each is kept in Warble's own preferences and handed to the store, which decides what
/// follows.
@MainActor
@Observable
final class NotchSettings {
    private static let key = "virtualTitle"
    private static let pauseDelayKey = "pauseDelay"
    private static let visibilityKey = "virtualNotch"
    private static let glowKey = "albumArtGlow"
    private static let cardSizeKey = "cardSize"
    private static let fontKey = "notchFont"
    private static let albumColourKey = "matchesAlbumColour"

    private let defaults: UserDefaults
    private let dispatch: (AppAction) -> Void

    var showsVirtualTitle: Bool {
        didSet {
            guard showsVirtualTitle != oldValue else { return }
            defaults.set(showsVirtualTitle, forKey: Self.key)
            log.notice("Title in a virtual notch \(self.showsVirtualTitle ? "on" : "off", privacy: .public)")
            dispatch(.virtualTitleChanged(showsVirtualTitle))
        }
    }

    var pauseDelay: PauseDelay {
        didSet {
            guard pauseDelay != oldValue else { return }
            defaults.set(pauseDelay.rawValue, forKey: Self.pauseDelayKey)
            log.notice("Pause delay \(self.pauseDelay.rawValue, privacy: .public)")
            dispatch(.pauseDelayChanged(pauseDelay))
        }
    }

    var virtualVisibility: VirtualNotchVisibility {
        didSet {
            guard virtualVisibility != oldValue else { return }
            defaults.set(virtualVisibility.rawValue, forKey: Self.visibilityKey)
            log.notice("Virtual notch \(self.virtualVisibility.rawValue, privacy: .public)")
            dispatch(.virtualVisibilityChanged(virtualVisibility))
        }
    }

    var cardSize: CardSize {
        didSet {
            guard cardSize != oldValue else { return }
            defaults.set(cardSize.rawValue, forKey: Self.cardSizeKey)
            log.notice("Card size \(self.cardSize.rawValue, privacy: .public)")
            dispatch(.cardSizeChanged(cardSize))
        }
    }

    var notchFont: NotchFont {
        didSet {
            guard notchFont != oldValue else { return }
            defaults.set(notchFont.rawValue, forKey: Self.fontKey)
            log.notice("Notch font \(self.notchFont.rawValue, privacy: .public)")
            dispatch(.fontChanged(notchFont))
        }
    }

    var matchesAlbumColour: Bool {
        didSet {
            guard matchesAlbumColour != oldValue else { return }
            defaults.set(matchesAlbumColour, forKey: Self.albumColourKey)
            log.notice("Text and bars follow the album colour \(self.matchesAlbumColour ? "on" : "off", privacy: .public)")
            dispatch(.albumColourChanged(matchesAlbumColour))
        }
    }

    var showsGlow: Bool {
        didSet {
            guard showsGlow != oldValue else { return }
            defaults.set(showsGlow, forKey: Self.glowKey)
            log.notice("Album-art glow \(self.showsGlow ? "on" : "off", privacy: .public)")
            dispatch(.glowChanged(showsGlow))
        }
    }

    init(defaults: UserDefaults = .standard, dispatch: @escaping (AppAction) -> Void) {
        self.defaults = defaults
        self.dispatch = dispatch
        showsVirtualTitle = defaults.bool(forKey: Self.key)
        virtualVisibility = defaults.string(forKey: Self.visibilityKey).flatMap(VirtualNotchVisibility.init) ?? .standard
        showsGlow = defaults.object(forKey: Self.glowKey) as? Bool ?? true
        cardSize = defaults.string(forKey: Self.cardSizeKey).flatMap(CardSize.init) ?? .standard
        notchFont = defaults.string(forKey: Self.fontKey).flatMap(NotchFont.init) ?? .system
        matchesAlbumColour = defaults.bool(forKey: Self.albumColourKey)
        pauseDelay = defaults.string(forKey: Self.pauseDelayKey).flatMap(PauseDelay.init) ?? .standard
    }

    /// Tells the store what was saved, once it exists.
    func start() {
        if showsVirtualTitle {
            dispatch(.virtualTitleChanged(true))
        }
        if virtualVisibility != .standard {
            dispatch(.virtualVisibilityChanged(virtualVisibility))
        }
        if !showsGlow {
            dispatch(.glowChanged(false))
        }
        if cardSize != .standard {
            dispatch(.cardSizeChanged(cardSize))
        }
        if notchFont != .system {
            dispatch(.fontChanged(notchFont))
        }
        if matchesAlbumColour {
            dispatch(.albumColourChanged(true))
        }
        if pauseDelay != .standard {
            dispatch(.pauseDelayChanged(pauseDelay))
        }
    }
}
