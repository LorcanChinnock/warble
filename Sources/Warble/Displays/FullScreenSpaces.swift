import AppKit
import os
import WarbleCore

private let log = Logger.warble("displays")

/// Which displays show a full-screen app now. macOS has no public way to tell: the window list needs Screen Recording for
/// window names, and a zoomed window with the Dock hidden has the same frame as a full-screen one. So it reads each
/// display's current Space from the window server, looked up at run time, and reports none where that's missing.
@MainActor
enum FullScreenSpaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    /// The window server's type for a full-screen app's Space; a desktop's is 0.
    private static let fullScreenType = 4

    private static let functions: (MainConnection, CopyDisplaySpaces)? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let main = dlsym(handle, "CGSMainConnectionID"), let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else {
            log.error("Can't read Spaces, so a full-screen app won't hide the notch")
            return nil
        }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(copy, to: CopyDisplaySpaces.self))
    }()

    /// The displays showing a full-screen app, by `NSScreen.uuid`. With Displays have separate Spaces off, every display
    /// shares one Space, which the window server names "Main".
    static func displays() -> Set<String> {
        guard let (main, copy) = functions, let spaces = copy(main())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var displays: Set<String> = []
        for display in spaces {
            guard let current = display["Current Space"] as? [String: Any], current["type"] as? Int == fullScreenType,
                  let id = display["Display Identifier"] as? String
            else { continue }
            if id == "Main" {
                displays.formUnion(NSScreen.screens.map(\.uuid))
            } else {
                displays.insert(id)
            }
        }
        return displays
    }
}
