import Foundation

/// Applies `action` to `state` at `now` and returns the work it calls for. It's pure: no clock, no timers and no I/O, so
/// the same state, action and time always give the same result.
public func reduce(_ state: inout AppState, _ action: AppAction, now: Date) -> [AppEffect] {
    let old = state
    var effects: [AppEffect] = []
    switch action {
    case .playbackReported(let playback):
        if playback == nil, state.playback != nil {
            // Hidden only if nothing follows in time; each report of nothing waits again from now.
            state.hideAt = now + AppState.hideDelay
        } else {
            show(playback, in: &state, at: now)
        }
    case .command(let command):
        // Shows what a command will do before the app reports back, so a click on play/pause answers at once. Skipping
        // waits for the app, since only it knows the next track, and the app's next report replaces the guess either way.
        // While a hide is pending there's no guess, since one would cancel the hide and keep a stopped track on screen.
        if state.hideAt == nil, let current = state.playback {
            let guess = current.guessing(command, at: now)
            if guess != current {
                show(guess, in: &state, at: now)
            }
        }
        effects.append(.send(command))
    case .openApp:
        if let playback = state.playback {
            effects.append(.openApp(bundleIdentifier: playback.bundleIdentifier, title: playback.title))
        }
    case .openArtist:
        if let playback = state.playback {
            effects.append(.openArtist(bundleIdentifier: playback.bundleIdentifier, title: playback.title))
        }
    case .setVolume(let volume):
        effects.append(.setVolume(volume))
    case .scrolled(let delta, let precise, let inverted, let volume, let isMuted):
        // An empty notch takes the hover for its note but not the volume, which is for what's playing.
        guard state.showsPlayback else { break }
        effects += VolumeScroll.effects(delta, precise: precise, inverted: inverted, volume: volume, isMuted: isMuted)
    case .scrubbed(let seconds):
        // Like a click on the scrubber: the bar moves at once, and the app's next report replaces the guess.
        guard state.showsPlayback, state.hideAt == nil, let current = state.playback, current.duration != nil else { break }
        let moved = current.seeked(to: current.elapsed(at: now) + seconds, at: now)
        show(moved, in: &state, at: now)
        effects.append(.send(.seek(to: moved.elapsed)))
    case .flicked(let next):
        // Nothing to skip while nothing plays, and `.command` would still send it to a hidden player.
        guard state.showsPlayback else { break }
        effects.append(.send(next ? .nextTrack : .previousTrack))
    case .volumeRead(let volume, let isMuted):
        state.volume = volume
        state.isMuted = isMuted
    case .selectOutput(let id):
        // Before the effect, so the read it ends with is already watched.
        state.outputSwitch.select(id, from: state.currentOutput, at: now)
        effects.append(.selectOutput(id))
    case .outputsRead(let outputs, let current):
        state.outputs = outputs
        state.currentOutput = current
        let hadNote = state.outputSwitch.kept != nil
        state.outputSwitch.observe(current: current, at: now)
        if !hadNote, state.outputSwitch.kept != nil {
            // The menu that was used to switch has closed and, with the pointer over it, the card is closing.
            state.notches.keepOpen(until: now + OutputSwitch.holdDuration, state.shared, at: now)
        }
    case .glowChanged(let on):
        state.showsGlow = on
    case .cardSizeChanged(let size):
        state.cardSize = size
    case .pauseDelayChanged(let delay):
        state.idle.pauseDelay = delay
    case .housingsChanged, .fullScreenChanged, .pointer, .hover, .menu, .dismiss, .virtualTitleChanged, .virtualVisibilityChanged:
        effects += state.notches.reduce(action, shared: state.shared, at: now)
    case .tick:
        if let hideAt = state.hideAt, hideAt <= now {
            show(nil, in: &state, at: now)
        }
        state.idle.advance(to: now)
        state.outputSwitch.advance(to: now)
        effects += state.notches.reduce(action, shared: state.shared, at: now)
    }
    effects += settle(&state, from: old, at: now)
    return effects
}

extension PlaybackState {
    /// What `command` will make of this state, as far as Warble can tell before the app reports back.
    func guessing(_ command: PlaybackCommand, at date: Date) -> PlaybackState {
        var guess = self
        switch command {
        case .play: guess = playing(true, at: date)
        case .pause: guess = playing(false, at: date)
        case .togglePlayPause: guess = playing(!isPlaying, at: date)
        case .seek(let position): guess = seeked(to: position, at: date)
        case .setShuffle(let mode): guess.shuffle = mode
        case .setRepeat(let mode): guess.repeatMode = mode
        case .nextTrack, .previousTrack: break
        }
        return guess
    }
}

private func show(_ playback: PlaybackState?, in state: inout AppState, at now: Date) {
    state.hideAt = nil
    state.playback = playback
    state.idle.handle(.playback(playback), at: now)
}

/// Brings everything that follows from the notches' states up to date, then asks for the effects whose reason changed.
/// Opening or closing a notch can hold off or allow Idle, which can show or hide a notch in turn, so it goes round until
/// nothing changes.
private func settle(_ state: inout AppState, from old: AppState, at now: Date) -> [AppEffect] {
    let oldShared = old.shared
    var shared = state.shared
    for _ in 0..<4 {
        shared = state.shared
        state.notches.settle(from: old.notches, oldShared: oldShared, shared: shared)
        let hovering = state.notches.isHovered(shared)
        guard hovering != state.hovering else { break }
        state.hovering = hovering
        state.idle.handle(hovering ? .hoverStarted : .hoverEnded, at: now)
    }
    shared = state.shared
    return state.notches.follow(shared, at: now)
}
