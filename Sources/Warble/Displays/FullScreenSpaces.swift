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

    private static let functions: (MainConnection, CopyDisplaySpaces)? = {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let main = dlsym(handle, "CGSMainConnectionID"), let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else {
            log.error("Can't read Spaces, so a full-screen app won't hide the notch")
            return nil
        }
        return (unsafeBitCast(main, to: MainConnection.self), unsafeBitCast(copy, to: CopyDisplaySpaces.self))
    }()

    /// The displays showing a full-screen app, by `NSScreen.uuid`.
    static func displays() -> Set<String> {
        guard let (main, copy) = functions, let spaces = copy(main())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return FullScreenDisplays.from(spaces: spaces, allDisplays: NSScreen.screens.map(\.uuid))
    }
}
