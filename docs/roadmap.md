# Roadmap

Each release has an issue, and each change in it is a sub-issue small enough for one pull request. The issues hold the detail, including the state, actions, effects and tests each change adds to the store (CONTRIBUTING.md › Adding a feature); this page is the overview. Release numbers are targets, and work can move between them.

## [0.1 beta: the notch shows what's playing](https://github.com/LorcanChinnock/warble/issues/2)

The first public beta: what's playing in the notch, playback and volume controls, the output picker, the virtual notch for other displays, and setup that asks for no permissions.

- [#3](https://github.com/LorcanChinnock/warble/issues/3) refactor: port Shot's app infrastructure
- [#4](https://github.com/LorcanChinnock/warble/issues/4) feat(notch): draw the notch panel in Hidden and Resting states
- [#5](https://github.com/LorcanChinnock/warble/issues/5) feat(model): hover intent state machine
- [#6](https://github.com/LorcanChinnock/warble/issues/6) feat(notch): Peek and Expanded states with a shape morph
- [#7](https://github.com/LorcanChinnock/warble/issues/7) feat(model): playback state with elapsed-time interpolation
- [#8](https://github.com/LorcanChinnock/warble/issues/8) build: bundle mediaremote-adapter
- [#9](https://github.com/LorcanChinnock/warble/issues/9) feat(now-playing): read and control playback through the adapter
- [#10](https://github.com/LorcanChinnock/warble/issues/10) feat(now-playing): AppleScript fallback for Spotify and Music
- [#11](https://github.com/LorcanChinnock/warble/issues/11) feat(player): playback controls in the expanded notch
- [#12](https://github.com/LorcanChinnock/warble/issues/12) feat(player): volume slider, and scroll on the notch for volume
- [#13](https://github.com/LorcanChinnock/warble/issues/13) spike: switching output devices, including AirPlay
- [#14](https://github.com/LorcanChinnock/warble/issues/14) feat(outputs): output device picker
- [#15](https://github.com/LorcanChinnock/warble/issues/15) spike: following more than one player
- [#16](https://github.com/LorcanChinnock/warble/issues/16) feat(model): source priority and ignore list
- [#18](https://github.com/LorcanChinnock/warble/issues/18) feat(notch): album-art glow and fallback gradient
- [#19](https://github.com/LorcanChinnock/warble/issues/19) feat(notch): Resting wings with album art and play-state bars
- [#20](https://github.com/LorcanChinnock/warble/issues/20) feat(model): toast queue
- [#21](https://github.com/LorcanChinnock/warble/issues/21) feat(notch): track-change toast
- [#22](https://github.com/LorcanChinnock/warble/issues/22) feat(displays): virtual notch on external displays and Macs without a notch
- [#23](https://github.com/LorcanChinnock/warble/issues/23) feat(doctor): explain why nothing is detected
- [#24](https://github.com/LorcanChinnock/warble/issues/24) feat(app): notch right-click menu, menu bar icon setting, open at login
- [#25](https://github.com/LorcanChinnock/warble/issues/25) feat(onboarding): welcome window
- [#26](https://github.com/LorcanChinnock/warble/issues/26) feat(settings): Settings window with General, Notch and Players cards
- [#27](https://github.com/LorcanChinnock/warble/issues/27) feat(accessibility): VoiceOver, keyboard control and Increase Contrast
- [#28](https://github.com/LorcanChinnock/warble/issues/28) perf: set budgets for hover latency, idle CPU, memory and launch
- [#29](https://github.com/LorcanChinnock/warble/issues/29) chore: final icon and brand mark
- [#30](https://github.com/LorcanChinnock/warble/issues/30) docs: demo player for site media
- [#31](https://github.com/LorcanChinnock/warble/issues/31) docs(site): landing page and 0.1 guide pages
- [#162](https://github.com/LorcanChinnock/warble/issues/162) docs: record site and README media with the demo player
- [#32](https://github.com/LorcanChinnock/warble/issues/32) ci(release): ship the first beta
- [#73](https://github.com/LorcanChinnock/warble/issues/73) feat(app): menu bar icon from the app icon's bars
- [#75](https://github.com/LorcanChinnock/warble/issues/75) ci: retry the adapter test on a timeout, as the app does
- [#76](https://github.com/LorcanChinnock/warble/issues/76) feat(notch): open straight to the full card after a short hover
- [#86](https://github.com/LorcanChinnock/warble/issues/86) fix(now-playing): stop the adapter when Warble is killed
- [#90](https://github.com/LorcanChinnock/warble/issues/90) feat(notch): reveal an idle card on hover when nothing is playing
- [#91](https://github.com/LorcanChinnock/warble/issues/91) feat(model): return to idle a while after pausing
- [#92](https://github.com/LorcanChinnock/warble/issues/92) feat(notch): animate between idle and playing
- [#93](https://github.com/LorcanChinnock/warble/issues/93) feat(settings): Shortcuts section
- [#114](https://github.com/LorcanChinnock/warble/issues/114) docs(site): a look of Warble's own, not Shot's
- [#121](https://github.com/LorcanChinnock/warble/issues/121) refactor(app): one tested store, injected dependencies and feature folders
- [#130](https://github.com/LorcanChinnock/warble/issues/130) feat(onboarding): first-run notch demo
- [#135](https://github.com/LorcanChinnock/warble/issues/135) fix(shortcuts): the notch's Escape and a toast's ⌘Z can unregister each other
- [#188](https://github.com/LorcanChinnock/warble/issues/188) feat(player): resume the last track after its app has quit, on a normal install
- [#185](https://github.com/LorcanChinnock/warble/issues/185) fix(player): the last-played card's play button does nothing once the app's session has gone

## [0.2: podcasts and virtual notch titles](https://github.com/LorcanChinnock/warble/issues/33)

Podcast skips, off until you turn them on, and the title in the middle of a virtual notch.

- [#37](https://github.com/LorcanChinnock/warble/issues/37) feat(player): skip 15 seconds and change speed for podcasts
- [#113](https://github.com/LorcanChinnock/warble/issues/113) feat(notch): show the title in the middle of a virtual notch

## [0.4: extras](https://github.com/LorcanChinnock/warble/issues/44)

Source chips, plus research into replacing the volume overlay.

- [#46](https://github.com/LorcanChinnock/warble/issues/46) spike: replacing the volume and brightness overlay ([findings](spikes/volume-brightness-overlay.md))
- [#17](https://github.com/LorcanChinnock/warble/issues/17) feat(player): source chips (parked: the code from [#241](https://github.com/LorcanChinnock/warble/pull/241) was reverted in [#245](https://github.com/LorcanChinnock/warble/issues/245) until mediaremote-adapter can report a second player)

## Removed

These shipped and were taken out again to keep Warble a small notch for the listener: swipe to skip, dragging the album art out, reopening browser tracks, the track-change message over full-screen apps and hiding from screen sharing ([#243](https://github.com/LorcanChinnock/warble/issues/243)), and, before them, notch activities, the developer group, stats, the waveform, the sleep timer, lyrics, the Shortcuts actions, and the command line and URL scheme ([#237](https://github.com/LorcanChinnock/warble/issues/237)).

The Shortcuts tab, its global shortcuts and the notch's keyboard mode were removed too ([#246](https://github.com/LorcanChinnock/warble/issues/246)).

## [1.0: translations](https://github.com/LorcanChinnock/warble/issues/49)

The first translations of the app.

- [#52](https://github.com/LorcanChinnock/warble/issues/52) feat(i18n): first translations
