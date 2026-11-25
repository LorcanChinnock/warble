import Foundation
import os
import WarbleModel

private let log = Logger.warble("settings")

/// What Settings chooses about the notch: whether a virtual notch shows the title in its middle, how long a paused song
/// stays, when a virtual notch is there, how big the open card is and the face of the notch's title. Each is kept in Warble's own preferences and handed to the store, which decides what
/// follows.
@MainActor
@Observable
final class NotchSettings {
    private static let key = "virtualTitle"
    private static let pauseDelayKey = "pauseDelay"
    private static let visibilityKey = "virtualNotch"
    private static let cardSizeKey = "cardSize"
    private static let fontKey = "notchFont"

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

    init(defaults: UserDefaults = .standard, dispatch: @escaping (AppAction) -> Void) {
        self.defaults = defaults
        self.dispatch = dispatch
        showsVirtualTitle = defaults.object(forKey: Self.key) as? Bool ?? true
        virtualVisibility = defaults.string(forKey: Self.visibilityKey).flatMap(VirtualNotchVisibility.init) ?? .standard
        cardSize = defaults.string(forKey: Self.cardSizeKey).flatMap(CardSize.init) ?? .standard
        notchFont = defaults.string(forKey: Self.fontKey).flatMap(NotchFont.init) ?? .system
        pauseDelay = defaults.string(forKey: Self.pauseDelayKey).flatMap(PauseDelay.init) ?? .standard
    }

    /// Tells the store what was saved, once it exists.
    func start() {
        if !showsVirtualTitle {
            dispatch(.virtualTitleChanged(false))
        }
        if virtualVisibility != .standard {
            dispatch(.virtualVisibilityChanged(virtualVisibility))
        }
        if cardSize != .standard {
            dispatch(.cardSizeChanged(cardSize))
        }
        if notchFont != .system {
            dispatch(.fontChanged(notchFont))
        }
        if pauseDelay != .standard {
            dispatch(.pauseDelayChanged(pauseDelay))
        }
    }
}
