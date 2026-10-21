# Performance budgets

Warble sits on screen the whole time something plays, so its cost is paid all day. Its mantra makes speed a promise: nothing may slow the hover → expand path or a click on play/pause, and when nothing is playing Warble uses no timers and no CPU. Each path below has a budget and a check, so a regression can't land unnoticed. The method comes from Shot (`docs/performance.md` in LorcanChinnock/shot).

## In CI: `make perf`

`Tests/WarbleCoreTests/PerfTests.swift` times the paths between a player reporting a change and the notch showing it, with `ContinuousClock`. After one warm-up run, it keeps the fastest of at least 15 runs spread over at least half a second. A busy runner can only add time, so the fastest run is the closest to what the work costs, and a slow spell would have to last the whole half second to fail a test. `make test` skips the suite. `make perf` and CI's **Perf** step run it alone, one test at a time, so other tests don't skew the timings.

CI runs it on the release pull request, which makes it part of the release gate, and on any pull request labelled `performance`. Label a pull request before you push when it changes `AdapterStream`, `ArtworkColours` or `LastPlayedStore`, or anything else on these paths, and run `make perf` yourself.

Each budget is 2× the baseline measured on the CI runner, which is slower than the reference Mac. The baseline is the slowest of three CI runs. That leaves room for a noisy runner but still fails a change that does the work again on every call: decoding the art again on every line makes a pause about 7× slower.

| Path | What's measured | Reference Mac | CI runner | Budget |
|---|---|---|---|---|
| New track | `AdapterStream.apply` of the line a new track arrives on, with a 600×600 JPEG cover as its art | 300 µs | TBD | TBD |
| Pause | `AdapterStream.apply` of a pause or play line, after a track with art | 4.1 µs | TBD | TBD |
| Artwork colours | `ArtworkColours(data:)` of a 600×600 JPEG cover, for the expanded card's glow | 676 µs | TBD | TBD |
| Idle card art | `LastPlayedStore.thumbnail` of a 600×600 JPEG cover to 112 pixels, for the idle card | 624 µs | TBD | TBD |

To change a budget, measure again, then update both this table and `Budget` in `PerfTests.swift`.

## Locally: `make perf-app`

`scripts/perf.sh` measures an installed WarbleDev (`/Applications/WarbleDev.app` by default, or a path you pass). CI can't run it, because it needs the pointer and the notch. Run it before each release, after `make app`.

It moves the pointer and clicks for about four minutes, so leave the Mac alone while it runs. It needs Accessibility permission for the terminal, and nothing playing when it starts: it asks the adapter and stops if anything is. It quits WarbleDev and the installed Warble, since both draw in the notch, and reopens Warble at the end if it was running. The pointer goes back where it was.

The app emits `OSSignposter` signposts under its bundle identifier, in category `perf`, which the script reads with `log show --signpost`. Instruments shows them too.

- **Ready** marks when the notch is set up and the shortcuts are registered at launch. Its message gives the time since the process started.
- **Expand** runs from the input that opens a notch to the first frame of the morph, the next frame of its display after the change is committed. Its end message gives the cause and the milliseconds since the input: `hover ms=35.5` counts from when the hover delay ended, so a timer that fires late counts too, and `click ms=44.4` from the click's event. The 0.25 s morph that follows is the design, not the work, so the budget stops at the first frame.
- **Play/pause** runs the same way from a click on play/pause, a key in the open notch or a shortcut to the first frame that shows the new state.

The first frame waits for the display's next refresh, so these include up to a frame of waiting as well as the work: 17 ms on the reference Mac's 60 Hz display.

The script:

1. Launches the app three times and takes the median **launch → ready** time.
2. Waits 20 seconds, then measures **idle CPU** and **wakeups** for a minute with nothing playing, counting the adapter's Perl processes as Warble's.
3. Launches the preview track (`-notchPreviewState resting`), which plays without a player, so runs repeat. It waits 20 seconds and measures **CPU** and **wakeups** at rest for 30 seconds, then the **memory footprint**. The adapter doesn't run in the preview, so this is the notch's own cost.
4. Hovers over the notch ten times and clicks it ten times, moving off it after each, and reports the median **hover → expanded** and **click → expanded** times.
5. Opens the notch and clicks Pause and Play ten times, and reports the median **click → play/pause shown** time.

It exits non-zero if a metric is over budget or couldn't be measured.

| Metric | Reference Mac | Budget |
|---|---|---|
| Launch → ready | 145 ms | 205 ms |
| Idle CPU, nothing playing | 0.0% | at most 0.1% |
| Wakeups, nothing playing | 0.1 a second | at most 0.2 a second |
| CPU playing, notch at rest | 0.0% | at most 0.5% |
| Wakeups playing, notch at rest | 0.13 a second | at most 0.3 a second |
| Memory playing | 17 MB | 26 MB |
| End of hover delay → expanded | 35.5 ms | 55 ms |
| Click → expanded | 44.4 ms | 70 ms |
| Click → play/pause shown | 10.4 ms | 20 ms |

The timings and memory budgets are about 1.5× the baseline, the median of five runs. The CPU and wakeup budgets are absolute, since the promise is none at all. They're all set in `scripts/perf.sh`, so change both together.

**Wakeups** count each time a thread of Warble's starts running again, from its context switches. A timer wakes the app without using measurable CPU, so this is what catches one: a 1-second timer gives 1.33 a second and fails. macOS itself wakes any app now and then, about once every 10 seconds once it has settled, and more in its first seconds, so the budget allows twice that, and any timer of 5 seconds or less fails. `top`'s own idle wakeup column stays at 0 even for a process that wakes twice a second, so the script doesn't use it.

**CPU at rest** is the app's own. The play-state bars run in Core Animation, so their cost lands in WindowServer, not Warble: about 1.7% of a core at 8 fps, as measured in `PlayStateBars`.

## Reference Mac

MacBook Air (Mac16,13), Apple M4, 16 GB, macOS 27.0.1, built-in 60 Hz display only. The `make perf` baselines come from debug builds, as `swift test` makes them. The `make perf-app` baselines come from the build `make app` installs.
