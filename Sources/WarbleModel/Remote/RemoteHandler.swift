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
                return .success(now: NowPlayingSnapshot(state(), volume: volume.volume, at: clock.now))
            case .send(.output(let name)):
                let choices = AudioOutput.choices(outputs.all)
                guard let output = choices.matching(name) else {
                    let available = choices.map(\.name).joined(separator: ", ")
                    throw .usage("output", choices.isEmpty
                        ? "no sound outputs are available"
                        : "no single output matches \"\(name)\"; the outputs are \(available)")
                }
                dispatch(.selectOutput(output.id))
            case .send(.volume(let percent)):
                guard volume.volume != nil else {
                    throw .unavailable("the Mac's current sound output has no volume Warble can change")
                }
                dispatch(.setVolume(Double(percent) / 100))
            case .send(let command):
                if let action = command.action {
                    dispatch(action)
                }
            case .version, .help:
                break
            }
            return .success()
        } catch {
            return .failure(error)
        }
    }
}
