# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Warble is a macOS 15+ app that shows what's playing in the notch and controls it. It's a SwiftPM package (Swift 6 language mode, strict concurrency) whose only dependency is Sparkle. Its repository layout, tooling and release pipeline come from Shot (`LorcanChinnock/shot`); when you need a pattern this repo doesn't have yet, look there first. `docs/roadmap.md` lists the planned work, one GitHub issue per change.

## Mantra

By default, Warble is calm: a small, fast notch that shows what's playing and stays out of the way. Lyrics, the live waveform, stats and extra gestures are built in, but they start off.

- Nothing may slow the hover → expand path or a click on play/pause.
- When nothing is playing, Warble draws nothing and uses no CPU: no timers, no polling.
- The default is the simplest state, and every extra starts off.

## Who uses Warble

Design and write for the first person on this list; the later ones opt in to more.

- **The listener.** Wants play/pause, skip and to see what's on. Never opens Settings. Every default is set for them.
- **The podcast and audiobook listener.** Skips 15 seconds, changes the speed, sets a sleep timer.
- **The music fan.** Turns on lyrics and listening stats, switches speakers.
- **The multi-display user.** Uses the virtual notch on external displays and Macs without a notch, and sets rules per display.
- **The developer.** Uses the `warble` command, `warble://` links, Shortcuts and the MCP server.

What this means in practice:
- UI strings, Settings and the user guide speak to everyone. Avoid jargon (MCP, CLI, JSON) outside the developer-facing parts.
- Developer features stay in their own Settings card and guide pages, off by default.

## Commands

```bash
make test                         # WarbleModel and WarbleCore unit tests (Swift Testing)
make test-linux                   # WarbleModel tests in Docker on Linux, as CI runs them
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
2. **Run the dev build:** `make run` builds, installs `/Applications/WarbleDev.app` and launches it. Confirm the running binary with `pgrep -lf WarbleDev`. The ux-qa skill runs `build/WarbleDev.app` from `make bundle` without installing it.
3. **When finished, quit and uninstall the dev build,** then reopen the release if it was running:
   ```bash
   pkill -x WarbleDev
   rm -rf /Applications/WarbleDev.app build/WarbleDev.app   # or $INSTALL_DIR/WarbleDev.app if you set it
   open /Applications/Warble.app
   ```

## Architecture

Three targets:
- `Sources/WarbleModel`: logic that needs only Foundation, so CI builds and tests it on Linux: notch geometry (`MenuBar`), and as the roadmap lands, playback state and its interpolation, the hover state machine, source priority, the toast queue and the lyrics parser. It may import CoreGraphics only inside `#if canImport(CoreGraphics)`. Linux Foundation has `CGFloat`, `CGPoint`, `CGSize` and `CGRect`, but not `CGPath`, `CGColor` or `CGImage`.
- `Sources/WarbleCore`: logic that needs Apple frameworks but no window, display or permission: preferences, and later the now-playing sources, Core Audio devices and artwork colours.
- `Sources/Warble`: AppKit and SwiftUI that need a real session. `WarbleApp` is a `MenuBarExtra` with an `AppDelegate` adaptor; `Updater` wraps Sparkle.

**If logic can be tested without a window, it goes in WarbleModel with a test, or in WarbleCore if it needs an Apple framework.** Tests are top-level `@Test func` with sentence-style names: `Tests/WarbleModelTests` (run on Linux) and `Tests/WarbleCoreTests` (macOS). The app target has no tests.

Now playing: since macOS 15.4, only Apple-signed processes can read now-playing information through the private MediaRemote framework. The plan (#8) runs ungive/mediaremote-adapter, BSD-3-licensed, under `/usr/bin/perl`, which is Apple-signed, and reads its JSON stream. Keep everything that touches it behind the `NowPlayingSource` protocol, so a macOS change means replacing one implementation. The protocol, `PlaybackState` and `PlaybackCommand` live in WarbleModel; `PlaybackState.elapsed(at:)` runs the position on from the last report, so the progress bar needs no timer of its own.

Settings: keys and defaults live in WarbleCore `Preferences`. Views read them with `@Setting(PreferenceKey.x)`, which takes the default `Preferences` registers, from `SettingsStore` (`Sources/Warble/Settings`). A test checks every such key has a registered default.

Design: Warble's look is Native, its own and not Shot's; don't bring over Shot's Brutal tokens or controls. The notch is pure black so it merges with the camera housing, with the system font, white marks and grey for anything secondary, and no accent colour. Its tokens live in `Native` (`Sources/Warble/Design/Native.swift`), beside `NSView(hosting:)` and `ScaledFont`, which follows Settings › General › Text size.

Notch: `NotchController` (`Sources/Warble/Notch`) puts `NotchPanel` over the built-in display's notch in a `NotchState`, at the frame `NotchLayout` works out, and follows display changes. AppKit snaps windows to whole points, so the panel draws its shape at the notch's exact height, which can be a half point. `HoverIntent` (WarbleModel) decides when the pointer opens the notch into Peek and Expanded and closes it again: it takes timestamped events and returns the next deadline instead of running timers, so `NotchController` schedules one timer at most. The controller feeds it from a tracking area over only the camera housing while resting and the whole panel once open, a click on the panel, and, only while open, a click elsewhere or Escape (a temporary `HotkeyCenter` key, so no permission is needed). Between states the shape morphs on one spring while the content cross-fades; with Reduce Motion the shape changes at once and only the content fades. The panel grows before a morph and shrinks after it, so nothing is clipped. Nothing is playing until playback is read (#9); to see the notch, launch with `open build/WarbleDev.app --args -notchPreviewState resting`, which shows a preview track, and hover or click it. `Toast` shows a short message near the bottom of the screen under the pointer. `HotkeyCenter` registers the global shortcuts of `WarbleAction`, none of which has one by default.

Website: `site/` is the Astro site for warble.lorcanchinnock.com, built and deployed by Cloudflare Workers Builds (see `site/README.md`). The user guide lives in `site/src/guide/`, one Markdown file per page at `/docs/<slug>/`, in file name order. Each file's front matter gives its `title`, a one-line `summary` and its `group` (the groups are in `site/src/lib/guide-files.ts`). Write pages as tasks, in second person: numbered steps, `<kbd>⌘⇧4</kbd>` for keys, and `> [!TIP]` or `> [!NOTE]` callouts. The site also renders `CHANGELOG.md` directly. release-please ignores `site/`.

Concurrency: UI and model types are `@MainActor`. Heavy work runs in `Task.detached`.

## Rules enforced by `make lint`

- Use `NSView(hosting:)`, never `NSHostingView(rootView:)`/`NSHostingController`; a plain hosting view crashes when content changes under a visible window. `HostingView.swift`, which defines the helper, is exempt.
- Use `@Setting`, never `@AppStorage`; `@AppStorage` updates late, so views show inconsistent state.
- Don't use `onTapGesture(count: 2)` next to a single tap; every single click waits out the double-click interval. Use one `onTapGesture` and read `NSApp.currentEvent?.clickCount`.
- WarbleModel and its tests import only Foundation, Synchronization and Testing, plus CoreGraphics inside `#if canImport(CoreGraphics)`.
- Every `runs-on: macos-*` needs a `# macOS: <reason>` comment on the line above.

## CI

The repository is public, so GitHub's runners are free, but the free plan runs only 5 macOS jobs at once, so macOS runs can queue (`.github/workflows/ci.yml`):
- Every PR runs two required checks. `test` is Linux: `scripts/lint.sh` and WarbleModel's tests, which keeps WarbleModel portable. `macos` builds the app, checks the strings catalog, compiles for Intel, and runs every test. On push to `main`, `warm-cache.yml` only builds, to save the Linux build cache PRs restore.
- release-please opens its release PR as the repository's GitHub App (`release.yml`), so its runs start without approval. The repository has auto-merge turned off: an admin merges the release PR by hand once its checks pass.
- `release.yml` runs `make test` on the tagged commit before it signs anything, because a `docs:`, `test:` or `ci:` commit merged after the release PR's checks can change what's released.
- Run `make lint` and `make test` before every push, plus `make test-linux` when you change WarbleModel, and push once per PR where you can, so CI is a check rather than a debugger.

## Conventions

- UI strings go through `Resources/Localizable.xcstrings` (CONTRIBUTING.md › Strings and translations). Pass literals to localizing APIs: SwiftUI views, or `String(localized:)` for AppKit titles and `String` properties. WarbleModel can't (no `String(localized:)` on Linux), so its labels live in WarbleCore. Logs and text that scripts read stay English. After adding strings, run `make strings` and commit the catalog; `make lint` and CI fail while it's stale.
- PR titles use Conventional Commits (`feat(notch): …`, `fix(player): …`). PRs are squash-merged and release-please generates versions and `CHANGELOG.md`, so never edit the version or tags by hand.
- Every PR links an issue or sub-issue: put `Closes #N` (or `Part of #N` when it doesn't finish the issue) in the PR body. Create the issue before starting any work, as a sub-issue of its release's umbrella issue.
- Any substantial change or new feature keeps docs in line in the same PR: the user guide in `site/src/guide/`, `README.md`, the landing page `site/src/pages/index.astro`, and `docs/roadmap.md` if it changes the plan. `CHANGELOG.md` is generated, so don't edit it.
- Only `make dist` builds `Warble.app` with the Sparkle feed. Every other build is `WarbleDev.app` (bundle ID `dev.lorcan.Warble.dev`, executable `WarbleDev`, scheme `warble-dev://`, no feed), so dev builds never self-update or replace the installed release. `scripts/bundle.sh` does the renaming.
- To QA UI changes by driving the real app, use the `.agents/skills/ux-qa` skill.
