import Foundation
import os
import WarbleModel

private let log = Logger.warble("settings")

/// What Settings chooses about the notch: whether a virtual notch shows the title in its middle, which starts off, and
/// how long a paused song stays. Each is kept in Warble's own preferences and handed to the store, which decides what
/// follows.
@MainActor
@Observable
final class NotchSettings {
    private static let key = "virtualTitle"
    private static let pauseDelayKey = "pauseDelay"

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

    init(defaults: UserDefaults = .standard, dispatch: @escaping (AppAction) -> Void) {
        self.defaults = defaults
        self.dispatch = dispatch
        showsVirtualTitle = defaults.bool(forKey: Self.key)
        pauseDelay = defaults.string(forKey: Self.pauseDelayKey).flatMap(PauseDelay.init) ?? .standard
    }

    /// Tells the store what was saved, once it exists.
    func start() {
        if showsVirtualTitle {
            dispatch(.virtualTitleChanged(true))
        }
        if pauseDelay != .standard {
            dispatch(.pauseDelayChanged(pauseDelay))
        }
    }
}
