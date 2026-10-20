# Roadmap

Each release has an issue, and each change in it is a sub-issue small enough for one pull request. The issues hold the detail; this page is the overview. Release numbers are targets, and work can move between them.

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
- [#17](https://github.com/LorcanChinnock/warble/issues/17) feat(player): source chips
- [#18](https://github.com/LorcanChinnock/warble/issues/18) feat(notch): album-art glow and fallback gradient
- [#19](https://github.com/LorcanChinnock/warble/issues/19) feat(notch): Resting wings with album art and play-state bars
- [#20](https://github.com/LorcanChinnock/warble/issues/20) feat(model): toast queue
- [#21](https://github.com/LorcanChinnock/warble/issues/21) feat(notch): track-change toast
- [#22](https://github.com/LorcanChinnock/warble/issues/22) feat(displays): virtual notch on external displays and Macs without a notch
- [#23](https://github.com/LorcanChinnock/warble/issues/23) feat(doctor): explain why nothing is detected
- [#24](https://github.com/LorcanChinnock/warble/issues/24) feat(app): notch right-click menu, menu bar icon setting, open at login
- [#25](https://github.com/LorcanChinnock/warble/issues/25) feat(onboarding): welcome window and first-run notch demo
- [#26](https://github.com/LorcanChinnock/warble/issues/26) feat(settings): Settings window with General, Notch and Players cards
- [#27](https://github.com/LorcanChinnock/warble/issues/27) feat(accessibility): VoiceOver, keyboard control and Increase Contrast
- [#28](https://github.com/LorcanChinnock/warble/issues/28) perf: set budgets for hover latency, idle CPU, memory and launch
- [#29](https://github.com/LorcanChinnock/warble/issues/29) chore: final icon and brand mark
- [#30](https://github.com/LorcanChinnock/warble/issues/30) docs: demo player for site media
- [#31](https://github.com/LorcanChinnock/warble/issues/31) docs(site): landing page and 0.1 guide pages
- [#32](https://github.com/LorcanChinnock/warble/issues/32) ci(release): ship the first beta
- [#73](https://github.com/LorcanChinnock/warble/issues/73) feat(app): menu bar icon from the app icon's bars
- [#75](https://github.com/LorcanChinnock/warble/issues/75) ci: retry the adapter test on a timeout, as the app does
- [#76](https://github.com/LorcanChinnock/warble/issues/76) feat(notch): open straight to the full card after a short hover
- [#86](https://github.com/LorcanChinnock/warble/issues/86) fix(now-playing): stop the adapter when Warble is killed

## [0.2: lyrics, gestures and podcasts](https://github.com/LorcanChinnock/warble/issues/33)

Synced lyrics, gestures and podcast controls, each off until you turn it on.

- [#34](https://github.com/LorcanChinnock/warble/issues/34) feat(model): LRC parser and current-line lookup
- [#35](https://github.com/LorcanChinnock/warble/issues/35) feat(lyrics): synced lyrics from LRCLIB
- [#36](https://github.com/LorcanChinnock/warble/issues/36) feat(gestures): swipe to skip, force click for lyrics, drag the album art out
- [#37](https://github.com/LorcanChinnock/warble/issues/37) feat(player): skip 15 seconds and change speed for podcasts
- [#38](https://github.com/LorcanChinnock/warble/issues/38) feat(notch): toasts in full screen, and hiding during screen sharing

## [0.3: for developers](https://github.com/LorcanChinnock/warble/issues/39)

The `warble` command, `warble://` links, an MCP server for AI assistants, and Shortcuts actions.

- [#40](https://github.com/LorcanChinnock/warble/issues/40) feat(cli): the warble command
- [#41](https://github.com/LorcanChinnock/warble/issues/41) feat(url): warble:// links
- [#42](https://github.com/LorcanChinnock/warble/issues/42) feat(agents): MCP server and one-click install
- [#43](https://github.com/LorcanChinnock/warble/issues/43) feat(shortcuts): Shortcuts actions

## [0.4: extras](https://github.com/LorcanChinnock/warble/issues/44)

The live waveform, a sleep timer and listening stats, plus research into replacing the volume overlay.

- [#45](https://github.com/LorcanChinnock/warble/issues/45) feat(waveform): live waveform from a Core Audio tap
- [#46](https://github.com/LorcanChinnock/warble/issues/46) spike: replacing the volume and brightness overlay
- [#47](https://github.com/LorcanChinnock/warble/issues/47) feat(player): sleep timer
- [#48](https://github.com/LorcanChinnock/warble/issues/48) feat(stats): weekly listening stats, kept on this Mac

## [1.0: notch activities for other apps](https://github.com/LorcanChinnock/warble/issues/49)

A way for other Mac apps to show activities in the notch, starting with Shot, plus translations and stable developer interfaces.

- [#50](https://github.com/LorcanChinnock/warble/issues/50) spike: notch activities protocol
- [#51](https://github.com/LorcanChinnock/warble/issues/51) feat(activities): notch activities API
- [#52](https://github.com/LorcanChinnock/warble/issues/52) feat(i18n): first translations
- [#53](https://github.com/LorcanChinnock/warble/issues/53) docs: stable command line, URL scheme and MCP reference
