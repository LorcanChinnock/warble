import Foundation

/// Applies `action` to `state` at `now` and returns the work it calls for. It's pure: no clock, no timers and no I/O, so
/// the same state, action and time always give the same result.
public func reduce(_ state: inout AppState, _ action: AppAction, now: Date) -> [AppEffect] {
    let old = state
    var notice: Notice<TrackToast>?
    var effects: [AppEffect] = []
    // First, so a touch or something playing ends the first-run demo before the action meets the notch it drew over.
    effects += state.onboarding.reduce(action, shared: state.shared, at: now)
    switch action {
    case .playbackReported(let playback):
        if playback == nil, state.playback != nil {
            // Hidden only if nothing follows in time; each report of nothing waits again from now.
            state.hideAt = now + AppState.hideDelay
        } else {
            if let playback {
                notice = TrackToast.notice(from: state.playback, to: playback)
            }
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
        if let bundleIdentifier = state.playback?.bundleIdentifier ?? state.lastPlayed?.bundleIdentifier {
            effects.append(.openApp(bundleIdentifier: bundleIdentifier))
        }
    case .resumeLastPlayed:
        // Idle with a session still reporting means a paused track, which the app can resume. With no session, a play
        // command would go nowhere, so open the track if it has a link. Spotify reopens on the track it had, so launch it
        // and play. Anything else just opens its app.
        if state.playback != nil {
            return reduce(&state, .command(.play), now: now)
        } else if let url = state.lastPlayed?.resumeURL {
            effects.append(.openLink(url))
        } else if let player = state.lastPlayed.flatMap({ ScriptedPlayer(rawValue: $0.bundleIdentifier) }), player == .spotify {
            effects.append(.launchAndPlay(player))
        } else if let bundleIdentifier = state.lastPlayed?.bundleIdentifier {
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
    case .lastPlayedLoaded, .remembered:
        effects += state.last.reduce(action, shared: state.shared, at: now)
    case .adapterChanged, .factsGathered, .playersChanged, .automationDenied, .fallbackReported, .notNow:
        effects += state.doctor.reduce(action, shared: state.shared, at: now)
    case .housingsChanged, .fullScreenChanged, .pointer, .hover, .menu, .showDoctor, .dismiss,
        .virtualTitleChanged:
        effects += state.notches.reduce(action, shared: state.shared, at: now)
    case .stayVisibleChanged(let delay):
        state.idle.delay = delay
        state.idle.advance(to: now)
    case .trackToastChanged:
        effects += state.toast.reduce(action, shared: state.shared, at: now)
    case .launched, .welcomeClosed:
        break
    case .tick:
        if let hideAt = state.hideAt, hideAt <= now {
            show(nil, in: &state, at: now)
        }
        state.idle.advance(to: now)
        effects += state.toast.reduce(action, shared: state.shared, at: now)
        effects += state.notches.reduce(action, shared: state.shared, at: now)
    }
    effects += settle(&state, from: old, at: now)
    // After Idle has had its say, so a track that's no longer shown has nothing to announce.
    state.toast.announce(notice, shared: state.shared, isOpen: state.notches.isOpen(state.shared), at: now)
    effects += state.last.follow(state.shared, at: now)
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
        // The open card shows the track, so a toast has nothing left to say, even once the notch closes again. Nor has one
        // for a track no longer shown, which would come back if the same track reported again before its deadline.
        if state.notches.isOpen(shared) || !state.showsPlayback {
            state.toast.dismiss(at: now)
            shared = state.shared
        }
        let hovering = state.notches.isHovered(shared)
        guard hovering != state.hovering else { break }
        state.hovering = hovering
        state.idle.handle(hovering ? .hoverStarted : .hoverEnded, at: now)
    }
    shared = state.shared
    var effects = state.notches.follow(shared, at: now)
    // Opening a notch checks again whatever the Doctor found, in case the user fixed it, such as in System Settings,
    // which tells Warble nothing.
    if state.notches.watchesClicks, !old.notches.watchesClicks, state.doctor.adapter != .working {
        effects.append(state.doctor.refresh())
    }
    return effects
}
