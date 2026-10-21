import Foundation

/// Applies `action` to `state` at `now` and returns the work it calls for. It's pure: no clock, no timers and no I/O, so
/// the same state, action and time always give the same result.
public func reduce(_ state: inout AppState, _ action: AppAction, now: Date) -> [AppEffect] {
    switch action {
    case .playbackReported(let playback):
        if playback == nil, state.playback != nil {
            // Hidden only if nothing follows in time; each report of nothing waits again from now.
            state.hideAt = now + AppState.hideDelay
        } else {
            show(playback, in: &state, at: now)
        }
    case .hoverChanged(let hovering):
        guard hovering != state.hovering else { break }
        state.hovering = hovering
        state.idle.handle(hovering ? .hoverStarted : .hoverEnded, at: now)
    case .stayVisibleChanged(let delay):
        state.idle.delay = delay
        state.idle.advance(to: now)
    case .tick:
        if let hideAt = state.hideAt, hideAt <= now {
            show(nil, in: &state, at: now)
        }
        state.idle.advance(to: now)
    }
    return []
}

private func show(_ playback: PlaybackState?, in state: inout AppState, at now: Date) {
    state.hideAt = nil
    state.playback = playback
    state.idle.handle(.playback(playback), at: now)
}
