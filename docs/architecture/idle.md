# Idle

Read this before changing when the notch goes back to Idle, which draws nothing: `NotchState.hidden`, with the wings slid back behind the housing. Back to the [architecture index](../../CLAUDE.md#architecture).

After a pause, `IdleAfterPause` (WarbleModel) decides when the notch goes back to Idle: `PreferenceKey.stayVisibleAfterPausing` seconds (10 by default) after the pause, a new track or the pointer leaving. While the pointer is on a notch or a card is open it never goes Idle; playing again cancels the countdown, and a source that stops reporting goes Idle at once. Like `HoverIntent`, it takes timestamped events and returns the next deadline, and it's part of `AppState`, so its deadline joins the store's one timer, and there's none while playing or Idle. Before it, `reduce` keeps a report of nothing from hiding the notch for `AppState.hideDelay` (1.5 seconds), longer than the gap a source leaves between tracks, so a skip doesn't close the notch under the pointer.
