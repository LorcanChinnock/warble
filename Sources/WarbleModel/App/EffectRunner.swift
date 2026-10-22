import Foundation

/// Carries out the effects that go through a port, and hands the rest, which need AppKit, to `platform`.
@MainActor
public final class EffectRunner {
    private let hotkeys: any HotkeyRegistrar
    /// Carries out the effects that need AppKit. The notch sets it, since it owns what they change.
    public var platform: (AppEffect) -> Void = { _ in }
    /// Where a key press goes back in as an action. The store sets it once both exist.
    public var dispatch: (AppAction) -> Void = { _ in }
    /// Whether Escape is Warble's now, so letting go never takes another temporary key, such as a toast's ⌘Z.
    private var holdsEscape = false

    public init(hotkeys: any HotkeyRegistrar) {
        self.hotkeys = hotkeys
    }

    public func perform(_ effect: AppEffect) {
        switch effect {
        case .takeEscape(true):
            guard !holdsEscape else { return }
            holdsEscape = hotkeys.registerTemporary(.escape) { [weak self] in
                self?.dispatch(.dismiss(except: nil))
            }
        case .takeEscape(false):
            guard holdsEscape else { return }
            hotkeys.unregisterTemporary()
            holdsEscape = false
        case .watchClicksOutside, .followVolume, .notchOpened:
            platform(effect)
        }
    }
}

extension KeyCombo {
    /// Escape with no modifiers.
    public static let escape = KeyCombo(keyCode: 53, modifiers: 0)
}
