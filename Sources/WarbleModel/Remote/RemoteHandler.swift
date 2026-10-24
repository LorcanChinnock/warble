import Foundation

/// Answers the command line. It parses the arguments, and then does what the matching button does: it dispatches the same
/// action, so a command shows at once and goes to the player as an effect, like a click. `now` reads what the state says.
/// The socket calls it on the main actor, where the store runs.
@MainActor
public final class RemoteHandler {
    private let state: () -> AppState
    private let dispatch: (AppAction) -> Void
    private let volume: any VolumeControl
    private let outputs: any AudioOutputs
    private let clock: any WallClock

    public init(
        state: @escaping () -> AppState, dispatch: @escaping (AppAction) -> Void, volume: any VolumeControl,
        outputs: any AudioOutputs, clock: any WallClock
    ) {
        self.state = state
        self.dispatch = dispatch
        self.volume = volume
        self.outputs = outputs
        self.clock = clock
    }

    public func handle(_ request: RemoteRequest) -> RemoteResponse {
        do throws(RemoteCommandError) {
            switch try WarbleCommand.parse(request.arguments) {
            case .now:
                return .success(now: nowPlaying())
            case .send(let command):
                try run(command)
            case .version, .help:
                break
            }
            return .success()
        } catch {
            return .failure(error)
        }
    }

    /// What's playing, as `now` answers it. Shortcuts' Get now playing reads it too.
    public func nowPlaying() -> NowPlayingSnapshot {
        NowPlayingSnapshot(state(), volume: volume.volume, at: clock.now)
    }

    /// Does what the command's button does, or throws why it can't. Every way in goes through here, so a link, the command
    /// line and Shortcuts agree on what a command needs.
    public func run(_ command: RemoteCommand) throws(RemoteCommandError) {
        switch command {
        case .output(let name):
            let choices = AudioOutput.choices(outputs.all)
            guard let output = choices.matching(name) else {
                let available = choices.map(\.name).joined(separator: ", ")
                throw .usage("output", choices.isEmpty
                    ? "no sound outputs are available"
                    : "no single output matches \"\(name)\"; the outputs are \(available)")
            }
            dispatch(.selectOutput(output.id))
        case .volume(let percent):
            guard volume.volume != nil else {
                throw .unavailable("the Mac's current sound output has no volume Warble can change")
            }
            dispatch(.setVolume(Double(percent) / 100))
        default:
            if let action = command.action {
                dispatch(action)
            }
        }
    }

    /// Moves the sound to the output with this Core Audio ID, which Shortcuts picked from the list of outputs. It throws
    /// when that output has gone since, such as AirPods that were put away.
    public func selectOutput(id: UInt32) throws(RemoteCommandError) {
        guard let output = AudioOutput.choices(outputs.all).first(where: { $0.id == id }) else {
            throw .unavailable("that sound output isn't connected")
        }
        dispatch(.selectOutput(output.id))
    }

    /// The outputs Shortcuts offers, the same ones the notch lists.
    public func outputChoices() -> [AudioOutput] {
        AudioOutput.choices(outputs.all)
    }
}
