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
        if let bundleIdentifier = state.playback?.bundleIdentifier {
            effects.append(.openApp(bundleIdentifier: bundleIdentifier))
        }
    case .setVolume(let volume):
        effects.append(.setVolume(volume))
    case .scrolled(let delta, let precise, let inverted, let volume, let isMuted):
        effects += VolumeScroll.effects(delta, precise: precise, inverted: inverted, volume: volume, isMuted: isMuted)
    case .volumeRead(let volume, let isMuted):
        state.volume = volume
        state.isMuted = isMuted
    case .selectOutput(let id):
        effects.append(.selectOutput(id))
    case .outputsRead(let outputs, let current):
        state.outputs = outputs
        state.currentOutput = current
    case .glowChanged(let on):
        state.showsGlow = on
    case .pauseDelayChanged(let delay):
        state.idle.pauseDelay = delay
    case .housingsChanged, .fullScreenChanged, .pointer, .hover, .menu, .dismiss, .virtualTitleChanged, .virtualVisibilityChanged:
        effects += state.notches.reduce(action, shared: state.shared, at: now)
    case .tick:
        if let hideAt = state.hideAt, hideAt <= now {
            show(nil, in: &state, at: now)
        }
        state.idle.advance(to: now)
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
