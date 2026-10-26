# Performance budgets

Warble sits on screen the whole time something plays, so its cost is paid all day. Its mantra makes speed a promise: nothing may slow the hover → expand path or a click on play/pause, and when nothing is playing Warble uses no timers and no CPU. Each path below has a budget and a check, so a regression can't land unnoticed. The method comes from Shot (`docs/performance.md` in LorcanChinnock/shot).

## In CI: `make perf`

`Tests/WarbleCoreTests/PerfTests.swift` times the paths between a player reporting a change and the notch showing it, with `ContinuousClock`. After one warm-up run, it keeps the fastest of at least 15 runs spread over at least half a second. A busy runner can only add time, so the fastest run is the closest to what the work costs, and a slow spell would have to last the whole half second to fail a test. `make test` skips the suite. `make perf` and CI's **Perf** step run it alone, one test at a time, so other tests don't skew the timings.

CI runs it on the release pull request, which makes it part of the release gate, and on any pull request labelled `performance`. Label a pull request before you push when it changes `AdapterStream` or `ArtworkColours`, or anything else on these paths, and run `make perf` yourself.

Each budget is 2× the baseline measured on the CI runner, which is slower than the reference Mac. The baseline is the slowest of three CI runs. That leaves room for a noisy runner but still fails a change that does the work again on every call: decoding the art again on every line makes a pause about 7× slower.

| Path | What's measured | Reference Mac | CI runner | Budget |
|---|---|---|---|---|
| New track | `AdapterStream.apply` of the line a new track arrives on, with a 600×600 JPEG cover as its art | 300 µs | 506 µs | 1,012 µs |
| Pause | `AdapterStream.apply` of a pause or play line, after a track with art | 4.1 µs | 8.1 µs | 16.2 µs |
| Artwork colours | `ArtworkColours(data:)` of a 600×600 JPEG cover, for the expanded card's glow | 676 µs | 1,404 µs | 2,809 µs |

To change a budget, measure again, then update both this table and `Budget` in `PerfTests.swift`.

## Reference Mac

MacBook Air (Mac16,13), Apple M4, 16 GB, macOS 27.0.1, built-in 60 Hz display only. The `make perf` baselines come from debug builds, as `swift test` makes them.
