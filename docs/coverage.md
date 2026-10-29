# Test coverage

`make coverage` runs the tests with `--enable-code-coverage` and prints line coverage per file for WarbleModel and WarbleCore, lowest first. It's a map of where tests are missing, not a gate. `Sources/Warble` has no tests and isn't measured.

Measured on 29 October 2026, without PerfTests:

| Target | Lines covered |
| --- | --- |
| WarbleModel | 1343 of 1374 (97.7%) |
| WarbleCore | 632 of 1157 (54.6%) |

WarbleModel's gaps are a handful of lines in `AppState.swift` (33 of 43) and single lines elsewhere. WarbleCore's gaps are where the work is:

| File | Lines covered | Why |
| --- | --- | --- |
| `App/TimerScheduler.swift` | 0 of 26 | Wraps a real timer; nothing tests it |
| `Volume/CoreAudioOutputs.swift` | 0 of 98 | Calls Core Audio directly |
| `Volume/SystemVolume.swift` | 0 of 98 | Calls Core Audio directly |
| `Playback/ScriptSource.swift` | 20 of 196 | Runs AppleScript against players |
| `Playback/ArtistPage.swift` | 44 of 86 | Network and page parsing |
| `Playback/BrowserTabs.swift` | 49 of 92 | AppleScript against browsers |

Re-run `make coverage` rather than trusting these numbers; they go stale.
