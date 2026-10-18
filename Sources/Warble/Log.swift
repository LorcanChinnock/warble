import Foundation
import os

extension Logger {
    /// Logs under the app's bundle identifier, so forks with their own identifier keep their logs apart.
    static func warble(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Warble", category: category)
    }
}
