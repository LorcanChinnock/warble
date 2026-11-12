import Foundation

/// A new version that Sparkle found, as the update window offers it. It holds what the appcast item and Sparkle's update
/// state say, so the window's buttons and text follow the same rules Sparkle's own window did.
public struct UpdateOffer: Equatable, Sendable {
    /// How far Sparkle got with the update before showing it.
    public enum Stage: Equatable, Sendable {
        /// Nothing is downloaded yet, so Install and Relaunch starts the download.
        case notDownloaded
        /// An earlier session downloaded it, so Install and Relaunch only unpacks and installs it.
        case downloaded
        /// It's unpacked and waiting, so Warble can relaunch into it now or install it when Warble quits.
        case installing
    }

    public var version: String
    public var build: String
    public var installedVersion: String
    public var installedBuild: String
    public var stage: Stage
    /// The download's size from the feed, or nil when the feed gives none.
    public var downloadSize: UInt64?
    /// The feed marks it important, so Sparkle offers no Skip or Remind Me Tomorrow.
    public var isCritical: Bool
    /// A major upgrade, which can be skipped even when it's critical.
    public var isMajorUpgrade: Bool
    /// The feed has no download, only a page to read, so the main button opens that page.
    public var isInformationOnly: Bool

    public init(
        version: String, build: String, installedVersion: String, installedBuild: String, stage: Stage = .notDownloaded,
        downloadSize: UInt64? = nil, isCritical: Bool = false, isMajorUpgrade: Bool = false, isInformationOnly: Bool = false
    ) {
        self.version = version
        self.build = build
        self.installedVersion = installedVersion
        self.installedBuild = installedBuild
        self.stage = stage
        self.downloadSize = downloadSize.flatMap { $0 > 0 ? $0 : nil }
        self.isCritical = isCritical
        self.isMajorUpgrade = isMajorUpgrade
        self.isInformationOnly = isInformationOnly
    }

    /// The new and installed versions as the window names them. When the two read the same, each gets its build
    /// number, as Sparkle's own window does, so they never look identical.
    public var versions: (new: String, installed: String) {
        guard version == installedVersion else {
            return (version, installedVersion)
        }
        return ("\(version) (\(build))", "\(installedVersion) (\(installedBuild))")
    }

    /// What the line under the title says beyond "You have 0.1.0": the download's size while there's one to come, and
    /// that Warble relaunches, unless there's nothing to install.
    public var message: UpdateOfferMessage {
        if isInformationOnly {
            return .installedOnly
        }
        if stage == .notDownloaded, let downloadSize {
            return .downloadAndRelaunch(size: downloadSize)
        }
        return .relaunch
    }
}

/// The parts of the offer's message, which WarbleCore turns into a sentence.
public enum UpdateOfferMessage: Equatable, Sendable {
    /// "You have 0.1.0. The download is 6 MB, and Warble quits and reopens to finish, which takes a few seconds."
    case downloadAndRelaunch(size: UInt64)
    /// "You have 0.1.0. Warble quits and reopens to finish, which takes a few seconds."
    case relaunch
    /// "You have 0.1.0." The update is a page to read.
    case installedOnly
}

/// What the offer's buttons are. Sparkle's own window decided the same things.
public struct UpdateOfferButtons: Equatable, Sendable {
    /// What the main button does.
    public enum Install: Equatable, Sendable {
        /// Downloads if needed, then installs and relaunches.
        case installAndRelaunch
        /// Opens the release's page, for a feed item with nothing to download.
        case learnMore
    }

    /// What the middle button says, if it shows.
    public enum Later: Equatable, Sendable {
        case hidden
        /// Puts the offer off until the next scheduled check, which is a day away.
        case remindTomorrow
        /// The update is already unpacked, so putting it off installs it when Warble quits.
        case installOnQuit
    }

    public var install: Install
    public var later: Later
    public var showsSkip: Bool
    /// Whether to show "Install updates automatically from now on". Sparkle offers it only while it may install updates
    /// by itself, and never for a release with nothing to download.
    public var showsAutomaticInstall: Bool

    /// - Parameters:
    ///   - offer: The version on offer.
    ///   - automaticallyChecks: Whether Check for updates automatically is on. Remind Me Tomorrow waits for the next
    ///     scheduled check, so it's hidden when there isn't one.
    ///   - allowsAutomaticUpdates: Sparkle's `allowsAutomaticUpdates`, true while automatic checks are on unless the
    ///     app turns automatic installs off.
    public init(offer: UpdateOffer, automaticallyChecks: Bool, allowsAutomaticUpdates: Bool) {
        install = offer.isInformationOnly ? .learnMore : .installAndRelaunch
        let mustInstall = offer.isCritical && !offer.isMajorUpgrade
        showsSkip = !mustInstall
        if mustInstall {
            later = .hidden
        } else if offer.stage == .installing {
            // Installing on quit needs no check, so it stays with automatic checks off.
            later = .installOnQuit
        } else {
            later = automaticallyChecks ? .remindTomorrow : .hidden
        }
        showsAutomaticInstall = allowsAutomaticUpdates && !offer.isInformationOnly
    }
}

/// How much of an update has downloaded, for the window's progress bar, its sizes and the time left.
public struct UpdateDownloadProgress: Equatable, Sendable {
    public private(set) var received: UInt64 = 0
    /// The size the server gave, or nil when it gave none.
    public private(set) var expected: UInt64?
    /// When the first bytes arrived, which the time left is measured from.
    private var started: Date?

    public init() {}

    public mutating func expect(_ length: UInt64) {
        expected = length > 0 ? length : nil
    }

    public mutating func receive(_ length: UInt64, at now: Date) {
        if started == nil, length > 0 {
            started = now
        }
        received += length
    }

    /// From 0 to 1, or nil while the size isn't known, when the window shows a moving bar instead.
    public var fraction: Double? {
        guard let expected, expected > 0 else {
            return nil
        }
        return min(Double(received) / Double(expected), 1)
    }

    /// The total, never under what's arrived.
    public var total: UInt64? {
        expected.map { max($0, received) }
    }

    /// Roughly how long the rest will take at the speed so far, in whole seconds, or nil until a second of data has
    /// arrived, when a guess would jump about, and once it's all here.
    public func secondsLeft(now: Date) -> Int? {
        guard let started, let expected, received < expected else {
            return nil
        }
        let elapsed = now.timeIntervalSince(started)
        guard elapsed >= 1, received > 0 else {
            return nil
        }
        let rate = Double(received) / elapsed
        return max(1, Int((Double(expected - received) / rate).rounded(.up)))
    }
}

/// Where the update window is, which `UpdateUserDriver` moves along as Sparkle reports each step.
public enum UpdatePhase: Equatable, Sendable {
    /// A check the person asked for is running.
    case checking
    /// A new version is on offer.
    case offer
    /// Downloading, with the bar filling as the bytes arrive.
    case downloading
    /// Unpacking and checking the download, from 0 to 1. It can't be cancelled.
    case preparing(Double)
    /// Downloaded and waiting for Relaunch Now.
    case ready
    /// Warble is quitting so the update can go in, and relaunches after.
    case installing
    /// Another installer replaced Warble while it ran, so it offers a relaunch.
    case installedWhileRunning(version: String)

    /// What closing the window, or pressing Esc, does. It's what Sparkle's own window did, plus the two states it never had.
    public var closing: UpdateClose {
        switch self {
        case .checking: .cancel
        case .offer: .remindLater
        case .downloading, .preparing: .hide
        case .ready: .installOnQuit
        case .installing: .refuse
        case .installedWhileRunning: .later
        }
    }

    /// Whether an update is downloading or unpacking, which the menus' update item shows as progress.
    public var isDownloading: Bool {
        switch self {
        case .downloading, .preparing: true
        default: false
        }
    }

    /// The window is 540 pt wide for the offer, with its release notes, and 500 for the rest.
    public var width: Double {
        self == .offer ? 540 : 500
    }
}

/// What closing the update window does.
public enum UpdateClose: Equatable, Sendable {
    /// Stops the check.
    case cancel
    /// Remind Me Tomorrow: the next scheduled check offers it again.
    case remindLater
    /// Closes the window and lets the download go on.
    case hide
    /// Later: Sparkle installs the update the next time Warble quits.
    case installOnQuit
    /// Later: nothing happens until Warble is next opened.
    case later
    /// Warble is already quitting to install, so the window stays.
    case refuse
}
