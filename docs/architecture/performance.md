# Performance

Read this before changing anything on the hover, expand or play/pause path, or adding a timer. Back to the [architecture index](../../CLAUDE.md#architecture).

`docs/performance.md` holds the budgets, the reference Mac and how each is measured. `Perf` (`Sources/Warble/App/Perf.swift`) emits signposts in category `perf`: `Ready` at launch, and `Expand` and `Play/pause`, which run from the input to the next frame of the display after the change (`Perf.untilNextFrame`, one display link that goes away after it fires), so they cost nothing until someone touches the notch. Instruments shows them. A timer shows as wakeups long before it shows as CPU, so check a new one with Activity Monitor's idle wakeups column or `sample`. `Tests/WarbleCoreTests/PerfTests.swift` (`make perf`) times the stream, artwork colours and idle-card art; `make test` skips it, and CI runs it on the release PR and on any PR labelled `performance`.
