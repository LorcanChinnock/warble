import Foundation

/// Applies `action` to `state` at `now` and returns the work it calls for. It's pure: no clock, no timers and no I/O, so
/// the same state, action and time always give the same result.
public func reduce(_ state: inout AppState, _ action: AppAction, now: Date) -> [AppEffect] {
    let old = state
    var notice: Notice<TrackToast>?
    var effects: [AppEffect] = []
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
    case .perform(let action):
        if let command = action.command {
            return reduce(&state, .command(command), now: now)
        }
        effects.append(.toggleKeyboard)
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
    case .skip(let seconds):
        // A seek from where it is now, kept within the track, so it shows at once like any seek. With nothing shown, or
        // a hide pending, there's no position to skip from, so it sends nothing.
        guard state.showsPlayback, state.hideAt == nil, let playback = state.playback else { break }
        return reduce(&state, .command(.seek(to: playback.position(skipping: seconds, at: now))), now: now)
    case .openApp:
        if let bundleIdentifier = state.playback?.bundleIdentifier ?? state.lastPlayed?.bundleIdentifier {
            effects.append(.openApp(bundleIdentifier: bundleIdentifier))
        }
    case .setVolume(let volume):
        effects.append(.setVolume(volume))
    case .scrolled(let delta, let across, let phase, let precise, let inverted, let volume, let isMuted):
        // Scrolling over the notch changes the volume. With swipe to skip on, a trackpad gesture goes one way only, so a
        // sideways swipe skips once and leaves the volume alone. A wheel has no gesture and only scrolls.
        guard state.swipeToSkip, precise, let phase else {
            effects += scroll(delta, precise: precise, inverted: inverted, volume: volume, isMuted: isMuted)
            break
        }
        switch state.swipe.handle(across: across, down: delta, phase: phase, inverted: inverted) {
        case .volume(let delta):
            effects += scroll(delta, precise: precise, inverted: inverted, volume: volume, isMuted: isMuted)
        case .skip(let command):
            // Skipping needs something to skip; with nothing playing the swipe does nothing.
            if state.showsPlayback, state.playback != nil {
                effects += [.send(command), .haptic]
            }
        case .nothing:
            break
        }
    case .volumeKey(let delta, let volume, let isMuted):
        if let volume {
            effects.append(.setVolume(NotchKey.volume(changing: isMuted ? 0 : volume, by: delta)))
        }
    case .volumeRead(let volume, let isMuted):
        state.volume = volume
        state.isMuted = isMuted
    case .selectOutput(let id):
        effects.append(.selectOutput(id))
    case .outputsRead(let outputs, let current):
        state.outputs = outputs
        state.currentOutput = current
    case .lastPlayedLoaded(let saved):
        // A track that played since Warble opened is newer than the one saved.
        if state.remembered == nil, let saved {
            state.lastPlayed = saved
        }
    case .remembered(let lastPlayed, let pass):
        guard pass == state.remembers else { break }
        state.lastPlayed = lastPlayed
        effects.append(.saveLastPlayed(lastPlayed))
    case .adapterChanged(let adapter):
        guard adapter != state.doctor.adapter else { break }
        let followed = state.doctor.adapter != .working
        state.doctor.adapter = adapter
        if (adapter != .working) != followed {
            effects.append(.followPlayers(adapter != .working))
        }
        effects.append(refreshDoctor(&state))
    case .factsGathered(let facts, let pass):
        guard pass == state.doctor.refreshes else { break }
        update(Doctor.checks(facts), in: &state.doctor)
    case .playersChanged, .automationDenied:
        effects.append(refreshDoctor(&state))
    case .fallbackReported:
        // Only while Automation fails, so a player that plays after the user allowed it clears the "!" without asking
        // macOS on every change of track.
        if state.doctor.checks.contains(where: { $0.kind == .automation && $0.outcome == .fail }) {
            effects.append(refreshDoctor(&state))
        }
    case .notNow:
        state.doctor.dismissed.formUnion(state.doctor.checks.filter { $0.outcome == .fail }.map(\.kind))
    case .housingsChanged(let housings):
        var surfaces: [String: AppState.Surface] = [:]
        for housing in housings {
            var surface = state.surfaces[housing.display] ?? AppState.Surface(housing)
            surface.isVirtual = housing.isVirtual
            surface.isAlwaysShown = housing.isAlwaysShown
            surface.isFullScreen = state.fullScreen.contains(housing.display)
            surfaces[housing.display] = surface
        }
        state.surfaces = surfaces
    case .fullScreenChanged(let displays):
        // A notch that stops answering starts its hover over in `settle`, so an open card closes.
        state.fullScreen = displays
        for display in state.surfaces.keys {
            state.surfaces[display]?.isFullScreen = displays.contains(display)
        }
    case .pointer(let display, let inside):
        guard let surface = state.surfaces[display], state.answersPointer(surface), inside != surface.pointerInside else { break }
        state.surfaces[display]?.pointerInside = inside
        handle(inside ? .pointerEntered : .pointerLeft, on: display, in: &state, at: now)
    case .hover(let display, let event):
        if event == .click || event == .keyboard {
            dismiss(in: &state, except: display, at: now)
        }
        if case .dragging(let dragging) = event {
            state.surfaces[display]?.isDragging = dragging
        }
        handle(event, on: display, in: &state, at: now)
    case .menu(let display, let open):
        state.surfaces[display]?.showsMenu = open
        handle(open ? .menuOpened : .menuClosed, on: display, in: &state, at: now)
    case .showDoctor(let display, let show):
        // From the resting "!", the click that follows opens the notch on the checks.
        state.surfaces[display]?.showsDoctor = show
    case .showLyrics(let display, let show):
        // Only from an open card, and only while there are lyrics to show; the button is there only then.
        guard let surface = state.surfaces[display], state.notchState(surface) == .expanded, !show || state.hasLyricsCard else { break }
        state.surfaces[display]?.showsLyrics = show
    case .dismiss(let except):
        dismiss(in: &state, except: except, at: now)
    case .stayVisibleChanged(let delay):
        state.idle.delay = delay
        state.idle.advance(to: now)
    case .idleHoverChanged(let idleHover):
        state.idleHover = idleHover
    case .trackToastChanged(let shows):
        state.showsTrackToast = shows
        if !shows {
            dismissToast(in: &state, at: now)
        }
    case .toastsInFullScreenChanged(let on):
        state.toastsInFullScreen = on
    case .lyricsChanged(let on):
        state.lyrics.turn(on: on)
    case .swipeToSkipChanged(let on):
        state.swipeToSkip = on
        state.swipe = Swipe()
    case .podcastSkipsChanged(let on):
        state.podcastSkips = on
    case .dragArtOutChanged(let on):
        state.dragArtOut = on
    case .hidesFromCaptureChanged(let on):
        state.hidesFromCapture = on
    case .virtualTitleChanged(let on):
        state.showsVirtualTitle = on
    case .lyricsLoaded(let lyrics, let pass):
        state.lyrics.loaded(lyrics, pass: pass)
    case .tick:
        if let hideAt = state.hideAt, hideAt <= now {
            show(nil, in: &state, at: now)
        }
        state.idle.advance(to: now)
        state.toasts.advance(to: now)
        for display in state.surfaces.keys {
            state.surfaces[display]?.hover.advance(to: now)
        }
    }
    effects += settle(&state, from: old, at: now)
    // After Idle has had its say, so a track that's no longer shown has nothing to announce.
    if let notice, state.showsTrackToast, state.showsPlayback, !isOpen(state) {
        state.toasts.post(notice, at: now)
    }
    if let playback = state.playback, playback != old.playback {
        effects += remember(playback, in: &state)
    }
    // Last, so the line follows whatever this action did: a new track, a seek, a pause, Idle or a tick.
    if let fetch = state.lyrics.update(for: state.showsPlayback ? state.playback : nil, at: now) {
        effects.append(fetch)
    }
    return effects
}

/// The volume a scroll of `delta` sets, with a light tick on a Force Touch trackpad at each tenth.
private func scroll(_ delta: Double, precise: Bool, inverted: Bool, volume: Double?, isMuted: Bool) -> [AppEffect] {
    guard let volume, delta != 0 else { return [] }
    let from = isMuted ? 0 : volume
    let to = VolumeScroll.volume(after: delta, from: from, precise: precise, inverted: inverted)
    guard to != from else { return [] }
    return VolumeScroll.crossesTick(from: from, to: to) ? [.setVolume(to), .haptic] : [.setVolume(to)]
}

/// Keeps `playback` as the last track played, with a small copy of its art, and saves it for the next launch. Only a new
/// track or new art does any work.
private func remember(_ playback: PlaybackState, in state: inout AppState) -> [AppEffect] {
    guard LastPlayed.changes(from: state.remembered, to: playback) else { return [] }
    state.remembered = playback
    state.remembers += 1
    return [.remember(playback, pass: state.remembers)]
}

/// Gathers the Doctor's facts again. While the adapter works no check needs macOS, so the facts take no work.
private func refreshDoctor(_ state: inout AppState) -> AppEffect {
    state.doctor.refreshes += 1
    return .gatherFacts(state.doctor.adapter, pass: state.doctor.refreshes)
}

private func update(_ checks: [Doctor.Check], in doctor: inout DoctorState) {
    guard checks != doctor.checks else { return }
    // A check that passes again can fail again later, and then it needs the "!".
    doctor.dismissed.subtract(checks.filter { $0.outcome != .fail }.map(\.kind))
    doctor.checks = checks
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

/// Passes `event` to the notch's `HoverIntent`, unless it takes no hover: a blank notch that doesn't open keeps none, so
/// playback starting under the pointer doesn't open it.
private func handle(_ event: HoverEvent, on display: String, in state: inout AppState, at now: Date) {
    guard let surface = state.surfaces[display], state.answersPointer(surface) else { return }
    state.surfaces[display]?.hover.handle(event, at: now)
}

private func dismiss(in state: inout AppState, except: String?, at now: Date) {
    for (display, surface) in state.surfaces where display != except && state.notchState(surface) == .expanded {
        state.surfaces[display]?.hover.handle(.dismiss, at: now)
    }
}

private func dismissToast(in state: inout AppState, at now: Date) {
    guard state.toasts.current != nil else { return }
    state.toasts.dismiss(at: now)
}

private func isOpen(_ state: AppState) -> Bool {
    state.surfaces.values.contains { state.notchState($0) == .expanded }
}

/// Brings everything that follows from the notches' states up to date, then asks for the effects whose reason changed.
/// Opening or closing a notch can hold off or allow Idle, which can show or hide a notch in turn, so it goes round until
/// nothing changes.
private func settle(_ state: inout AppState, from old: AppState, at now: Date) -> [AppEffect] {
    for _ in 0..<4 {
        for (display, surface) in state.surfaces {
            guard let before = old.surfaces[display] else { continue }
            if old.answersPointer(before), !state.answersPointer(surface) {
                // Start over, so a pointer still on the notch when it's drawn again is reported as entering again.
                state.surfaces[display]?.hover = HoverIntent()
                state.surfaces[display]?.pointerInside = false
                state.surfaces[display]?.isDragging = false
            }
            if old.notchState(before) == .expanded, state.notchState(surface) != .expanded {
                // The checks and the lyrics show until the notch closes; the next open shows the player again.
                state.surfaces[display]?.showsDoctor = false
                state.surfaces[display]?.showsLyrics = false
            }
        }
        // The open card shows the track, so a toast has nothing left to say, even once the notch closes again. Nor has one
        // for a track no longer shown, which would come back if the same track reported again before its deadline.
        if isOpen(state) || !state.showsPlayback {
            dismissToast(in: &state, at: now)
        }
        let hovering = state.surfaces.values.contains { state.notchState($0) == .expanded || $0.pointerInside }
        guard hovering != state.hovering else { break }
        state.hovering = hovering
        state.idle.handle(hovering ? .hoverStarted : .hoverEnded, at: now)
    }
    let open = state.surfaces.values.filter { state.notchState($0) == .expanded }
    var effects: [AppEffect] = []
    // A click anywhere else closes an open notch, and so does Escape with the pointer on it. Both stop at rest, so a
    // resting notch watches nothing and never takes Escape from the app in front. Escape is let go while a menu is
    // open, so the key reaches the menu and closes it, and while the art is dragged out, so it cancels the drag.
    let watchesClicks = !open.isEmpty
    if watchesClicks != state.watchesClicks {
        state.watchesClicks = watchesClicks
        effects.append(.watchClicksOutside(watchesClicks))
    }
    let takesEscape = open.contains(where: \.pointerInside) && !state.surfaces.values.contains { $0.showsMenu || $0.isDragging }
    if takesEscape != state.takesEscape {
        state.takesEscape = takesEscape
        effects.append(.takeEscape(takesEscape))
    }
    // Only the player's card has a slider and an output menu.
    let followsVolume = open.contains { state.card($0) == .player }
    if followsVolume != state.followsVolume {
        state.followsVolume = followsVolume
        effects.append(.followVolume(followsVolume))
    }
    // Opening a notch checks again whatever the Doctor found, in case the user fixed it, such as in System Settings,
    // which tells Warble nothing.
    if watchesClicks, !isOpen(old), state.doctor.adapter != .working {
        effects.append(refreshDoctor(&state))
    }
    return effects
}
