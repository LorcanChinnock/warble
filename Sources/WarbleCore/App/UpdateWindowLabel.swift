import Foundation
import WarbleModel

/// The update window's words that depend on the update, in the person's language. WarbleModel decides what to say;
/// these say it.
public enum UpdateWindowLabel {
    /// "Warble 0.2.0 is ready", the offer's title.
    public static func offerTitle(_ offer: UpdateOffer) -> String {
        String(localized: "Warble \(offer.versions.new) is ready")
    }

    /// The sentence under the offer's title.
    public static func offerMessage(_ offer: UpdateOffer) -> String {
        let installed = offer.versions.installed
        switch offer.message {
        case .downloadAndRelaunch(let size):
            let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: size), countStyle: .file)
            return String(localized: "You have \(installed). The download is \(size), and Warble quits and reopens to finish, which takes a few seconds.")
        case .relaunch:
            return String(localized: "You have \(installed). Warble quits and reopens to finish, which takes a few seconds.")
        case .installedOnly:
            return String(localized: "You have \(installed).")
        }
    }

    /// "3.2 of 6.0 MB", or "3.2 MB" while the size isn't known. Both numbers use the total's unit.
    public static func downloaded(_ progress: UpdateDownloadProgress) -> String {
        guard let total = progress.total else {
            return ByteCountFormatter.string(fromByteCount: Int64(clamping: progress.received), countStyle: .file)
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = total >= 1_000_000_000 ? .useGB : total >= 1_000_000 ? .useMB : .useKB
        formatter.zeroPadsFractionDigits = true
        formatter.includesUnit = false
        let received = formatter.string(fromByteCount: Int64(clamping: progress.received))
        formatter.includesUnit = true
        let whole = formatter.string(fromByteCount: Int64(clamping: total))
        return String(localized: "\(received) of \(whole)", comment: "How much of an update has downloaded: “3.2 of 6.0 MB”.")
    }

    /// "About 5 seconds left", or "About 2 minutes left".
    public static func timeLeft(seconds: Int) -> String {
        let duration = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
        return String(localized: "About \(duration) left", comment: "Time until an update finishes downloading: “About 5 seconds left”.")
    }

    /// "Downloading Warble 0.2.0".
    public static func downloadingTitle(version: String) -> String {
        String(localized: "Downloading Warble \(version)")
    }

    /// "Warble 0.2.0 is downloaded".
    public static func readyTitle(version: String) -> String {
        String(localized: "Warble \(version) is downloaded")
    }

    /// "Warble 0.2.0 is installed", when another installer replaced the running copy.
    public static func installedTitle(version: String) -> String {
        String(localized: "Warble \(version) is installed")
    }

    /// "What's new in 0.2.0", the release notes' name for VoiceOver.
    public static func notesName(version: String) -> String {
        String(localized: "What's new in \(version)")
    }
}

public extension ReleaseNotes.Kind {
    /// A group's heading in the release notes, or nil for changes listed before any heading.
    var label: String? {
        switch self {
        case .new: String(localized: "New", comment: "Release notes: the group of new features.")
        case .fixed: String(localized: "Fixed", comment: "Release notes: the group of bug fixes.")
        case .faster: String(localized: "Faster", comment: "Release notes: the group of speed improvements.")
        case .other(let heading): heading
        case .untitled: nil
        }
    }
}
