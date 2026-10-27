import Foundation
import os
import WarbleModel

private let log = Logger.warble("settings")

/// Whether a virtual notch shows the title in its middle, which starts off. It is kept in Warble's own preferences and
/// handed to the store, which decides where the title shows.
@MainActor
@Observable
final class NotchSettings {
    private static let key = "virtualTitle"

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

    init(defaults: UserDefaults = .standard, dispatch: @escaping (AppAction) -> Void) {
        self.defaults = defaults
        self.dispatch = dispatch
        showsVirtualTitle = defaults.bool(forKey: Self.key)
    }

    /// Tells the store what was saved, once it exists.
    func start() {
        if showsVirtualTitle {
            dispatch(.virtualTitleChanged(true))
        }
    }
}
