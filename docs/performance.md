# Performance budgets

Warble sits on screen the whole time something plays, so its cost is paid all day. It has to stay fast to open and close to free when nothing is playing. Each path below will get a budget and a check, so a regression can't land unnoticed. The issue `perf: set budgets for hover latency, idle CPU, memory and launch` measures the baselines and fills in the tables.

## In CI: `make perf`

Not set up yet. It will follow Shot's method (`docs/performance.md` in LorcanChinnock/shot). `Tests/WarbleCoreTests/PerfTests.swift` times the pure paths with `ContinuousClock`, keeping the fastest of at least 15 runs over at least half a second after one warm-up. `make test` skips the suite. CI runs it alone at the release gate, on the release pull request only. Each budget is 2× the baseline measured on the CI runner.

| Path | What's measured | Reference Mac | CI runner | Budget |
|---|---|---|---|---|
| Now-playing update | Merge one adapter stream line into the playback state | TBD | TBD | TBD |
| Artwork palette | Pick the glow colours from a 600×600 album cover | TBD | TBD | TBD |

## Locally: `make perf-app`

Not set up yet. `scripts/perf.sh` will drive an installed WarbleDev through its URL scheme and read `OSSignposter` signposts in category `perf`.

| Metric | Reference Mac | Budget |
|---|---|---|
| Launch → ready | TBD | TBD |
| Hover → peek visible | TBD | under 100 ms |
| Click → expanded, settled | TBD | under 250 ms |
| Idle CPU, nothing playing | TBD | about 0% |
| CPU while playing, notch at rest | TBD | under 1% |
| Memory while playing | TBD | under 60 MB |

The budgets in the last column are targets from the product plan. Replace them with measured ones.

## Reference Mac

To be recorded with the first baselines: model, chip, memory, macOS version and displays.
