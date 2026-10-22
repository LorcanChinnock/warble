import Foundation

/// Applies `action` to `state` at `now` and returns the work it calls for. It's pure: no clock, no timers and no I/O, so
/// the same state, action and time always give the same result.
public func reduce(_ state: inout AppState, _ action: AppAction, now: Date) -> [AppEffect] {
    let old = state
    var notice: Notice<TrackToast>?
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
    case .housingsChanged(let housings):
        var surfaces: [String: AppState.Surface] = [:]
        for housing in housings {
            var surface = state.surfaces[housing.display] ?? AppState.Surface(housing)
            surface.isVirtual = housing.isVirtual
            surface.isAlwaysShown = housing.isAlwaysShown
            surfaces[housing.display] = surface
        }
        state.surfaces = surfaces
    case .pointer(let display, let inside):
        guard let surface = state.surfaces[display], state.answersPointer(surface), inside != surface.pointerInside else { break }
        state.surfaces[display]?.pointerInside = inside
        handle(inside ? .pointerEntered : .pointerLeft, on: display, in: &state, at: now)
    case .hover(let display, let event):
        if event == .click || event == .keyboard {
            dismiss(in: &state, except: display, at: now)
        }
        handle(event, on: display, in: &state, at: now)
    case .menu(let display, let open):
        state.surfaces[display]?.showsMenu = open
        handle(open ? .menuOpened : .menuClosed, on: display, in: &state, at: now)
    case .showDoctor(let display, let show):
        // From the resting "!", the click that follows opens the notch on the checks.
        state.surfaces[display]?.showsDoctor = show
    case .dismiss(let except):
        dismiss(in: &state, except: except, at: now)
    case .attentionChanged(let needsAttention):
        state.needsAttention = needsAttention
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
    let effects = settle(&state, from: old, at: now)
    // After Idle has had its say, so a track that's no longer shown has nothing to announce.
    if let notice, state.showsTrackToast, state.showsPlayback, !isOpen(state) {
        state.toasts.post(notice, at: now)
    }
    return effects
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
            }
            if old.notchState(before) == .expanded, state.notchState(surface) != .expanded {
                // The checks show until the notch closes; the next open shows the player again.
                state.surfaces[display]?.showsDoctor = false
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
    // open, so the key reaches the menu and closes it.
    let watchesClicks = !open.isEmpty
    if watchesClicks != state.watchesClicks {
        state.watchesClicks = watchesClicks
        effects.append(.watchClicksOutside(watchesClicks))
    }
    let takesEscape = open.contains(where: \.pointerInside) && !state.surfaces.values.contains(where: \.showsMenu)
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
    if watchesClicks, !isOpen(old) {
        effects.append(.notchOpened)
    }
    return effects
}
