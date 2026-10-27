import Foundation
import os
import WarbleModel

private let log = Logger.warble("settings")

/// What Settings chooses about the notch: whether a virtual notch shows the title in its middle, which starts off, how
/// long a paused song stays, and whether the open card glows, which starts on. Each is kept in Warble's own preferences and handed to the store, which decides what
/// follows.
@MainActor
@Observable
final class NotchSettings {
    private static let key = "virtualTitle"
    private static let pauseDelayKey = "pauseDelay"
    private static let glowKey = "albumArtGlow"

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
        showsGlow = defaults.object(forKey: Self.glowKey) as? Bool ?? true
        pauseDelay = defaults.string(forKey: Self.pauseDelayKey).flatMap(PauseDelay.init) ?? .standard
    }

    /// Tells the store what was saved, once it exists.
    func start() {
        if showsVirtualTitle {
            dispatch(.virtualTitleChanged(true))
        }
        if !showsGlow {
            dispatch(.glowChanged(false))
        }
        if pauseDelay != .standard {
            dispatch(.pauseDelayChanged(pauseDelay))
        }
    }
}
