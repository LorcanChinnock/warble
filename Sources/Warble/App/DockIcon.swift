import AppKit

/// Warble has no Dock icon, so it takes one while one of its windows is open, to show in ⌘Tab and get the app menu.
/// Settings, the update window and the first-run window can be open together, so the icon goes only when the last of
/// them closes.
@MainActor
enum DockIcon {
    enum Holder: Hashable {
        case settings
        case update
        case firstRun
    }

    private static var holders: Set<Holder> = []

    static func show(for holder: Holder) {
        holders.insert(holder)
        NSApp.setActivationPolicy(.regular)
    }

    static func hide(for holder: Holder) {
        guard holders.remove(holder) != nil, holders.isEmpty else {
            return
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
