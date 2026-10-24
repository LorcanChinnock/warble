import AppIntents
import WarbleModel

/// The actions Shortcuts and Spotlight list for Warble. Each is one more way in for `RemoteCommand`, through the same
/// `RemoteHandler` as the command line, so it does what the notch's button does. They always work: nobody runs one
/// without building a shortcut first.
struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause"
    static let description = IntentDescription("Plays what's paused, or pauses what's playing.")

    @Dependency private var remote: RemoteHandler

    @MainActor
    func perform() async throws -> some IntentResult {
        try remote.run(.toggle)
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Track"
    static let description = IntentDescription("Skips to the next track.")

    @Dependency private var remote: RemoteHandler

    @MainActor
    func perform() async throws -> some IntentResult {
        try remote.run(.next)
        return .result()
    }
}

struct PreviousTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Previous Track"
    static let description = IntentDescription("Goes back to the previous track.")

    @Dependency private var remote: RemoteHandler

    @MainActor
    func perform() async throws -> some IntentResult {
        try remote.run(.previous)
        return .result()
    }
}

struct SetVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Volume"
    static let description = IntentDescription("Sets the volume of the Mac's sound output.")

    @Parameter(title: "Volume", description: "From 0 to 100.", default: 50, inclusiveRange: (0, 100))
    var percent: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set the volume to \(\.$percent)%")
    }

    @Dependency private var remote: RemoteHandler

    @MainActor
    func perform() async throws -> some IntentResult {
        try remote.run(.volume(percent: percent))
        return .result()
    }
}

struct SwitchOutputIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Sound Output"
    static let description = IntentDescription("Moves the Mac's sound to another output, such as AirPods.")

    @Parameter(title: "Output")
    var output: SoundOutputEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Play sound through \(\.$output)")
    }

    @Dependency private var remote: RemoteHandler

    @MainActor
    func perform() async throws -> some IntentResult {
        try remote.selectOutput(id: UInt32(output.id))
        return .result()
    }
}

struct GetNowPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Now Playing"
    static let description = IntentDescription("Gets the track that's playing, or the one that was paused.")

    @Dependency private var remote: RemoteHandler

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<NowPlayingEntity> {
        .result(value: NowPlayingEntity(remote.nowPlaying()))
    }
}

/// What the Shortcuts app and Spotlight list, with a shortcut phrase for each so Spotlight offers them by name.
struct WarbleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayPauseIntent(), phrases: ["Play or pause in \(.applicationName)"], shortTitle: "Play or Pause", systemImageName: "playpause.fill")
        AppShortcut(intent: NextTrackIntent(), phrases: ["Next track in \(.applicationName)"], shortTitle: "Next Track", systemImageName: "forward.fill")
        AppShortcut(intent: PreviousTrackIntent(), phrases: ["Previous track in \(.applicationName)"], shortTitle: "Previous Track", systemImageName: "backward.fill")
        AppShortcut(intent: GetNowPlayingIntent(), phrases: ["What's playing in \(.applicationName)"], shortTitle: "Get Now Playing", systemImageName: "music.note")
    }
}
