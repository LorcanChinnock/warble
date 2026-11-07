# Test coverage

`make coverage` runs the tests with Xcode's code coverage and prints line coverage per file for WarbleModel and WarbleCore, lowest first, from `xccov`. It's a map of where tests are missing, not a gate. `Sources/Warble` has no tests and isn't measured.

Measured on 7 November 2026, without PerfTests:

| Target | Lines covered |
| --- | --- |
| WarbleModel | 1601 of 1631 (98.2%) |
| WarbleCore | 800 of 1222 (65.5%) |

WarbleModel's gaps are a handful of lines in `AppState.swift` (40 of 50) and single lines elsewhere. WarbleCore's gaps are where the work is:

| File | Lines covered | Why |
| --- | --- | --- |
| `Favourite/ScriptedFavourites.swift` | 0 of 14 | Runs AppleScript against Music |
| `Volume/AudioHardware.swift` | 0 of 76 | Calls Core Audio directly |
| `Playback/ScriptSource.swift` | 20 of 196 | Runs AppleScript against players |
| `Playback/ArtistPage.swift` | 44 of 86 | Network and page parsing |
| `Playback/BrowserTabs.swift` | 49 of 92 | AppleScript against browsers |

Re-run `make coverage` rather than trusting these numbers; they go stale.
