# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Warble is a macOS 15+ app that shows what's playing in the notch and controls it. It's a SwiftPM package (Swift 6 language mode, strict concurrency) whose only Swift dependency is Sparkle; it also bundles mediaremote-adapter, a git submodule built with CMake. Its repository layout, tooling and release pipeline come from Shot (`LorcanChinnock/shot`); when you need a pattern this repo doesn't have yet, look there first. `docs/roadmap.md` lists the planned work, one GitHub issue per change.

## Mantra

By default, Warble is calm: a small, fast notch that shows what's playing and stays out of the way. Extras are built in, but they start off.

- Nothing may slow the hover → expand path or a click on play/pause.
- When nothing is playing, Warble draws nothing and uses no CPU: no timers, no polling.
- The default is the simplest state, and every extra starts off.

## Who uses Warble

Design and write for the first person on this list; the later ones opt in to more.

- **The listener.** Wants play/pause, skip and to see what's on. Never opens Settings. Every default is set for them.
- **The music fan.** Switches speakers.
- **The multi-display user.** Uses the virtual notch on external displays and Macs without a notch, and sets rules per display.

What this means in practice:
- UI strings, Settings and the user guide speak to everyone. Avoid jargon.

## Commands

```bash
make test                         # WarbleModel and WarbleCore unit tests (Swift Testing)
make test-linux                   # WarbleModel tests in Docker on Linux, as CI runs them
make perf                         # PerfTests alone: the timed paths with budgets in docs/performance.md
make lint                         # scripts/lint.sh: bans patterns that caused bugs (see below); on macOS also scripts/strings.sh --check
make strings                      # sync Resources/Localizable.xcstrings with the strings the build extracted
make build                        # swift build
make bundle                       # build and sign build/WarbleDev.app only
make run                          # build, install to /Applications/WarbleDev.app, relaunch
cd site && npm run dev            # the website (see site/README.md)
swift test --filter <testName>    # one test, e.g. --filter notchSitsBetweenTheMenuBarAreas
```

- With only the Command Line Tools selected, the Makefile pins the newest 26.x SDK and adds the testing plugin path, so a bare `swift build`/`swift test` can fail on SwiftUI macros. Prefer `make`, or prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Signing uses the `Warble Dev` certificate from `scripts/make-dev-cert.sh`, so permissions such as Automation survive rebuilds. Without it, `bundle.sh` signs ad hoc and warns.
- Logs: `/usr/bin/log stream --predicate 'subsystem == "dev.lorcan.Warble.dev"'` for WarbleDev, `dev.lorcan.Warble` for a release (in zsh, plain `log` is a builtin). Use `Logger.warble("category")` from `Sources/Warble/Log.swift`.

## Running and testing locally

Local builds are `WarbleDev.app`. A real installed version is `/Applications/Warble.app`, usually from Homebrew. Never install over, rename or delete `Warble.app`, or Homebrew loses track of it.

1. **Quit the installed release first:** `pkill -x Warble`. Both apps draw in the notch, so with both running their panels stack. `-x` matches the executable name exactly, so `pkill -x Warble` never kills WarbleDev, and `pkill -x WarbleDev` never kills the release.
2. **Run the dev build:** `make run` builds, installs `/Applications/WarbleDev.app` and launches it. Confirm the running binary with `pgrep -lf WarbleDev`.
3. **When finished, quit and uninstall the dev build,** then reopen the release if it was running:
   ```bash
   pkill -x WarbleDev
   rm -rf /Applications/WarbleDev.app build/WarbleDev.app   # or $INSTALL_DIR/WarbleDev.app if you set it
   open /Applications/Warble.app
   ```

## Architecture

Three targets:
- `Sources/WarbleModel`: logic that needs only Foundation, so CI builds and tests it on Linux: the app's state, `reduce` and their ports (`App/`), notch geometry, playback state and its interpolation, the hover state machine, source priority, the toast queue, the Doctor's checks. It may import CoreGraphics only inside `#if canImport(CoreGraphics)`. Linux Foundation has `CGFloat`, `CGPoint`, `CGSize` and `CGRect`, but not `CGPath`, `CGColor` or `CGImage`.
- `Sources/WarbleCore`: logic that needs Apple frameworks but no window, display or permission, including the real side of most ports: preferences, the now-playing sources, Core Audio volume and outputs (`SystemVolume`, `CoreAudioOutputs`), the last track's file (`LastPlayedFile`), artwork colours and `TimerScheduler`.
- `Sources/Warble`: AppKit and SwiftUI that need a real session. `WarbleApp` is a `MenuBarExtra` with an `AppDelegate` adaptor; `Updater` wraps Sparkle. It draws the store's state, turns AppKit events into actions and carries out the effects that need AppKit, and decides nothing else.

**If logic can be tested without a window, it goes in WarbleModel with a test, or in WarbleCore if it needs an Apple framework.** Tests are top-level `@Test func` with sentence-style names: `Tests/WarbleModelTests` (run on Linux) and `Tests/WarbleCoreTests` (macOS). The app target has no tests.

Concurrency: UI and model types are `@MainActor`. Heavy work runs in `Task.detached`.

The store, in short: `AppState` holds what the app decides, `AppAction` is everything that can happen to it, and `reduce(_:_:now:)` is a pure function from a state and an action to the next state and a list of `AppEffect`s. `Store` runs it synchronously on the main actor for each `dispatch`, so nothing sits between a hover or a click and the panel, and arms one timer for the earliest deadline, or none when nothing is due. Effects are data, carried out by `EffectRunner` through the ports in `App/Ports.swift` or by `PlatformEffects` where they need AppKit. The rest is in [the store](docs/architecture/store.md).

### Feature notes

Claude Code loads only this file, so read a feature's note before you change that feature. Each holds the feature's detail: what it decides, which types do it, and the edge cases behind it. When you change a feature, update its note in the same PR. To add a feature, see CONTRIBUTING.md › Adding a feature.

| Note | Read it before |
| --- | --- |
| [The store](docs/architecture/store.md) | changing `AppState`, `AppAction`, `reduce`, effects, ports or the timer |
| [Now playing](docs/architecture/now-playing.md) | touching the adapter, `ScriptSource`, `SourcePriority` or how a report becomes a `PlaybackState` |
| [Settings](docs/architecture/settings.md) | adding or changing a setting, the Settings window or Open at login |
| [Design](docs/architecture/design.md) | changing how anything looks, or adding a colour, font or control |
| [Doctor](docs/architecture/doctor.md) | changing the checks, their fixes or the "!" on the notch |
| [The notch](docs/architecture/notch.md) | changing the panel, its states and cards, hover, displays, toasts, scrolling or the keys it takes |
| [Accessibility](docs/architecture/accessibility.md) | adding or changing any control or label |
| [Idle](docs/architecture/idle.md) | changing when the notch goes back to Idle |
| [Idle card](docs/architecture/idle-card.md) | changing what the notch shows while nothing plays, or the last track played |
| [Motion](docs/architecture/motion.md) | changing how the notch moves between states |
| [Website](docs/architecture/website.md) | changing `site/` or the user guide |
| [Performance](docs/architecture/performance.md) | changing anything on the hover, expand or play/pause path, or adding a timer |

## Rules enforced by `make lint`

- Use `NSView(hosting:)`, never `NSHostingView(rootView:)`/`NSHostingController`; a plain hosting view crashes when content changes under a visible window. `HostingView.swift`, which defines the helper, is exempt.
- Use `@Setting`, never `@AppStorage`; `@AppStorage` updates late, so views show inconsistent state.
- Don't use `onTapGesture(count: 2)` next to a single tap; every single click waits out the double-click interval. Use one `onTapGesture` and read `NSApp.currentEvent?.clickCount`.
- WarbleModel and its tests import only Foundation, Synchronization and Testing, plus CoreGraphics inside `#if canImport(CoreGraphics)`.
- Every `runs-on: macos-*` needs a `# macOS: <reason>` comment on the line above.

## CI

The repository is public, so GitHub's runners are free, but the free plan runs only 5 macOS jobs at once, so macOS runs can queue (`.github/workflows/ci.yml`):
- Every PR runs two required checks. `test` is Linux: `scripts/lint.sh` and WarbleModel's tests, which keeps WarbleModel portable. `macos` builds the app, checks the strings catalog, compiles for Intel, and runs every test except `PerfTests`, which it runs only on the release PR and on PRs labelled `performance`. On push to `main`, `warm-cache.yml` only builds, to save the Linux build cache PRs restore.
- release-please opens its release PR as the repository's GitHub App (`release.yml`), so its runs start without approval. The repository has auto-merge turned off: an admin merges the release PR by hand once its checks pass.
- `release.yml` runs `make test` on the tagged commit before it signs anything, because a `docs:`, `test:` or `ci:` commit merged after the release PR's checks can change what's released.
- Run `make lint` and `make test` before every push, plus `make test-linux` when you change WarbleModel, and push once per PR where you can, so CI is a check rather than a debugger.

## Conventions

- UI strings go through `Resources/Localizable.xcstrings` (CONTRIBUTING.md › Strings and translations). Pass literals to localizing APIs: SwiftUI views, or `String(localized:)` for AppKit titles and `String` properties. WarbleModel can't (no `String(localized:)` on Linux), so its labels live in WarbleCore. Logs and text that scripts read stay English. After adding strings, run `make strings` and commit the catalog; `make lint` and CI fail while it's stale.
- PR titles use Conventional Commits (`feat(notch): …`, `fix(player): …`). PRs are squash-merged and release-please generates versions and `CHANGELOG.md`, so never edit the version or tags by hand.
- Every PR links an issue or sub-issue: put `Closes #N` (or `Part of #N` when it doesn't finish the issue) in the PR body. Create the issue before starting any work, as a sub-issue of its release's umbrella issue.
- Any substantial change or new feature keeps docs in line in the same PR: the user guide in `site/src/guide/`, `README.md`, the landing page `site/src/pages/index.astro`, and `docs/roadmap.md` if it changes the plan. `CHANGELOG.md` is generated, so don't edit it.
- Only `make dist` builds `Warble.app` with the Sparkle feed. Every other build is `WarbleDev.app` (bundle ID `dev.lorcan.Warble.dev`, executable `WarbleDev`, scheme `warble-dev://`, no feed), so dev builds never self-update or replace the installed release. `scripts/bundle.sh` does the renaming.
- For recordings that need a real player, `docs/demo/` is a made-up one with invented tracks and generated art (`docs/demo/README.md`). It's a separate package, outside every Make target and CI.
