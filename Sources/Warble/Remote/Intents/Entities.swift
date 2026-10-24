import AppIntents
import WarbleModel

/// A sound output Shortcuts can pick, from the list the notch shows.
struct SoundOutputEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sound Output"
    static let defaultQuery = SoundOutputQuery()

    let id: Int
    @Property(title: "Name")
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ output: AudioOutput) {
        id = Int(output.id)
        name = output.name
    }
}

struct SoundOutputQuery: EntityQuery {
    @Dependency private var remote: RemoteHandler

    @MainActor
    func entities(for identifiers: [Int]) async throws -> [SoundOutputEntity] {
        remote.outputChoices().filter { identifiers.contains(Int($0.id)) }.map(SoundOutputEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SoundOutputEntity] {
        remote.outputChoices().map(SoundOutputEntity.init)
    }
}

/// What Get Now Playing returns: the fields of `NowPlayingSnapshot`, so a shortcut can use any of them.
struct NowPlayingEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Now Playing"

    @Property(title: "Status")
    var status: String
    @Property(title: "Title")
    var title: String?
    @Property(title: "Artist")
    var artist: String?
    @Property(title: "Album")
    var album: String?
    @Property(title: "App")
    var app: String?
    @Property(title: "Position")
    var position: Int?
    @Property(title: "Duration")
    var duration: Int?
    @Property(title: "Volume")
    var volume: Int?

    var displayRepresentation: DisplayRepresentation {
        guard let title else { return DisplayRepresentation(title: "Nothing playing") }
        return DisplayRepresentation(title: "\(title)", subtitle: artist.map { "\($0)" })
    }

    init() {
        status = NowPlayingSnapshot.Status.stopped.rawValue
    }

    init(_ snapshot: NowPlayingSnapshot) {
        status = snapshot.status.rawValue
        title = snapshot.title
        artist = snapshot.artist
        album = snapshot.album
        app = snapshot.app
        position = snapshot.position
        duration = snapshot.duration
        volume = snapshot.volume
    }
}
