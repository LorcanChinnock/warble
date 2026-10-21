# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Warble is a macOS 15+ app that shows what's playing in the notch and controls it. It's a SwiftPM package (Swift 6 language mode, strict concurrency) whose only Swift dependency is Sparkle; it also bundles mediaremote-adapter, a git submodule built with CMake. Its repository layout, tooling and release pipeline come from Shot (`LorcanChinnock/shot`); when you need a pattern this repo doesn't have yet, look there first. `docs/roadmap.md` lists the planned work, one GitHub issue per change.

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

Now playing: since macOS 15.4, only Apple-signed processes can read now-playing information through the private MediaRemote framework. Warble bundles ungive/mediaremote-adapter, BSD-3-licensed: `scripts/bundle.sh` builds it with CMake from the `Vendor/mediaremote-adapter` submodule and puts `mediaremote-adapter.pl`, `MediaRemoteAdapter.framework` and `MediaRemoteAdapterTestClient` in `Contents/Resources`, signed but never linked. `AdapterSource` (WarbleCore) runs `/usr/bin/perl <script> <framework> <test client> stream --micros` with absolute paths, since `/usr/bin/perl` is Apple-signed, and each command as its own short run (`send 2`, `seek <microseconds>`). The stream starts behind a small Perl watchdog (`AdapterSource.watched`) that forks, waits on stdin and stops the stream when stdin closes. Warble holds the only write end, so the stream ends with Warble even after `kill -9` or a crash. `AdapterStream` (WarbleModel) turns the stream's lines into a `PlaybackState`; its tests replay output recorded from Safari in `Tests/WarbleModelTests/Fixtures`. A tab reports WebKit's GPU process as `bundleIdentifier` and the browser as `parentApplicationBundleIdentifier`, so the parent wins. When the stream exits on its own, `AdapterSupervisor` (WarbleModel) runs `test`, which exits 0 when the adapter still works, before starting it again with a growing delay. `test` times out now and then on a working adapter (exit 3 or 4), so those are retried; other failures stop it until Warble is opened again. CONTRIBUTING.md › Updating the adapter explains how to bump the pin. When more than one app reports playback, `SourcePriority` (WarbleModel) picks the one the notch follows: a pinned app, else the one that started playing last, never one on the ignore list (video calls by default). It takes reports per bundle identifier, so it doesn't care how sources are found. Keep everything that touches it behind the `NowPlayingSource` protocol, so a macOS change means replacing one implementation. The protocol, `PlaybackState` and `PlaybackCommand` live in WarbleModel; `PlaybackState.elapsed(at:)` runs the position on from the last report, so the progress bar needs no timer of its own. When the adapter isn't bundled or `AdapterSource` gives up, which ends its `states`, `ScriptSource` (WarbleCore) follows Music and Spotify with AppleScript instead: it reads a player when the player posts its distributed change notification, scripts only a running player, and so asks for Automation permission only then. Never run `osascript` against an app without a timeout, and don't script QuickTime.

Settings: keys and defaults live in WarbleCore `Preferences`. Views read them with `@Setting(PreferenceKey.x)`, which takes the default `Preferences` registers, from `SettingsStore` (`Sources/Warble/Settings`). A test checks every such key has a registered default. `SettingsWindow` opens Settings from the menu bar menu, or when Warble is opened again from Finder: a sidebar of `SettingsSection`s beside a grouped `Form` of standard controls in the system appearance, not the notch's black. It takes a Dock icon while open and drops its content when it closes. Shortcuts has a row for each `WarbleAction` (`ShortcutRow`). `ShortcutRecorder` watches keys and clicks only while it records, and pauses `HotkeyCenter` meanwhile. `ShortcutRecording` (WarbleModel) decides what a pressed key does: cancel, clear, ask for a modifier, refuse a reserved or taken combo, or record it. `HotkeyCenter.start()` registers the shortcuts at launch and again whenever a `hotkey.*` key changes, exclusively, so macOS refuses one another app holds exclusively, and Settings shows it. A section or row arrives with its feature; Players comes later.

Design: Warble's look is Native, its own and not Shot's; don't bring over Shot's Brutal tokens or controls. The notch is pure black so it merges with the camera housing, with the system font, white marks and grey for anything secondary, and no accent colour. Its tokens live in `Native` (`Sources/Warble/Design/Native.swift`), beside `NSView(hosting:)` and `ScaledFont`, which follows Settings › General › Text size.

Doctor: `Doctor` (WarbleModel) turns facts into checks, each with a fix. The facts are the adapter's state, the macOS version, Automation for each scripted player and which players are open. Its words live in WarbleCore (`Doctor+Mac.swift`), which also asks macOS about Automation without prompting. `DoctorModel` gathers the facts only on events: the adapter going missing or giving up, a player opening or quitting, a script refused with -1743, and a notch opening. While the adapter works it asks macOS nothing. While a check fails, every notch rests with a "!", even with nothing playing, and opens on a card (`NotchCard.doctor`, taller than the player's) that lists the checks.

Notch: `NotchController` (`Sources/Warble/Notch`) keeps a `NotchSurface` for each camera housing that `VirtualNotch.housings` (WarbleModel) returns: the built-in display's notch, and a virtual one at the top centre of each display without a notch whose `VirtualNotchRule` asks for one. By default only the main display gets one, and only while no display has a real notch (the lid is closed, or the Mac has none). Rules are stored per display UUID under `PreferenceKey.virtualNotch`, and the menu bar menu and Settings › General both set them (`VirtualNotchPicker`). Each surface puts its `NotchPanel` over its housing in a `NotchState`, at the frame `NotchLayout` works out, while `PlayerModel` holds what's playing once for all of them. The controller lays them out again when displays or rules change. The panel stays off full-screen Spaces, so a full-screen app hides it. macOS reports the housing to the half point, so its edges and height can fall on half points. AppKit snaps windows to whole points, so the panel's window grows out to whole points on both sides (`NotchLayout.window(for:)`) and draws its shape centred, at the housing's exact width and height. The resting corners and wings follow the housing's height (`NotchLayout.cornerRadius`, `wing`), so they stay the same physical size at every display scale; `Tests/WarbleModelTests/MeasuredHousings.swift` holds what a 15-inch MacBook Air reports at each scale. `HoverIntent` (WarbleModel) decides when the pointer opens a notch into Expanded, after `expandDelay` or at once on a click, and closes it again: it takes timestamped events and returns the next deadline instead of running timers, so each surface schedules one timer at most. Each surface feeds it from a tracking area over only the camera housing while resting and the whole panel once open, a click on the panel, and, only while a notch is open, a click elsewhere or Escape (a temporary `HotkeyCenter` key, so no permission is needed). Between states the shape morphs on one spring while the content cross-fades; with Reduce Motion the shape changes at once and only the content fades. The panel grows before a morph and shrinks after it, so nothing is clipped. Expanded holds the playback controls. They send `PlaybackCommand`s through `NotchController`, which shows play/pause, a seek and the shuffle and repeat modes at once (`PlaybackState.playing(_:at:)`, `seeked(to:at:)`) and lets the app's next report replace that guess. `SystemVolume` (WarbleCore) reads and sets the default output's volume through Core Audio. `NotchController` listens for its changes only while Expanded shows the slider, and scrolling over the panel in any state changes it, as `VolumeScroll` (WarbleModel) works out. To see the notch without playing anything, launch with `open build/WarbleDev.app --args -notchPreviewState resting`, which shows a preview track instead of reading the adapter, and hover or click it. Add `-notchPreviewVirtual YES` to draw the virtual notch instead, on a Mac that has a notch. `Toast` shows a short message near the bottom of the screen under the pointer. Notices that slide out of the notch, such as a track change, are another thing: `ToastQueue` (WarbleModel) decides which one shows and for how long, with no timers of its own. `HotkeyCenter` registers the global shortcuts of `WarbleAction`, none of which has one by default.

Idle: after a pause, `IdleAfterPause` (WarbleModel) decides when the notch goes back to Idle: `PreferenceKey.stayVisibleAfterPausing` seconds (10 by default) after the pause, a new track or the pointer leaving. While the pointer is on a notch or a card is open it never goes Idle; playing again cancels the countdown, and a source that stops reporting goes Idle at once. Like `HoverIntent`, it takes timestamped events and returns the next deadline, so `NotchController` schedules one timer at most, and none while playing or Idle.

Idle card: while Idle, each surface is in `NotchState.idle`, its panel exactly over the housing, black on a real one and clear on a virtual one (the panel sets `ignoresMouseEvents = false` so a clear panel still takes the pointer). Only the housing counts for the hover, as at rest, and `HoverIntent` opens it into Expanded with `NotchCard.idle`, as wide as the player's card and `NotchLayout.idleDrop` below the housing. `NotchState(_:isPlaying:needsAttention:idleHover:)` and `NotchCard(isPlaying:needsAttention:showsDoctor:)` (WarbleModel) decide which state and card each surface draws; with `PreferenceKey.idleHover` set to `nothing`, Idle is Hidden and no panel shows. The card shows `PlayerModel.lastPlayed`, which `NotchController` keeps whenever `LastPlayed.changes(from:to:)` says a report is a new track or new art, and saves through `LastPlayedStore` (WarbleCore) to `LastPlayed.json` in Application Support, with the art shrunk to 112 pixels, off the main thread. Resume sends `togglePlayPause`; the art opens the app. Preview it with `open build/WarbleDev.app --args -notchPreviewState idle`, adding `-notchPreviewLastPlayed NO` for the card with nothing played yet.

Motion: `NotchSurface.update` sets `NotchModel.state`, `card` and `isPlaying` together inside one `Native.morph`, so every change of state or card, such as resuming from the idle card or playback stopping under the full card, morphs the shape and cross-fades the content; it grows the panel before the morph and shrinks it after, and `NotchPanel.show` lays the content out at the new size first so the shape stays centred. Content is keyed by `ContentID` and comes and goes with `ContentTransition`: in after `NotchMotion.contentDelay`, out in `contentOut`. What it shows is passed in as values, so content on its way out keeps the track that stopped. As the resting wings appear, the art grows from `NotchMotion.artScale` and `BarsView` raises the bars one after another (`NotchMotion.barDelay`) in Core Animation, then loops them at 8 fps; they drop as the notch leaves Resting, and their animations go with the view. The timings live in `NotchMotion` (WarbleModel). With Reduce Motion the shape changes at once and only the content fades.

Website: `site/` is the Astro site for warble.lorcanchinnock.com, deployed from each release's tag by `.github/workflows/site.yml`, which `release.yml` calls, so it describes the version people can install. Merging a site change to `main` doesn't deploy it (see `site/README.md` › Deploying). The user guide lives in `site/src/guide/`, one Markdown file per page at `/docs/<slug>/`, in file name order. Each file's front matter gives its `title`, a one-line `summary` and its `group` (the groups are in `site/src/lib/guide-files.ts`). Write pages as tasks, in second person: numbered steps, `<kbd>⌘⇧4</kbd>` for keys, and `> [!TIP]` or `> [!NOTE]` callouts. The site also renders `CHANGELOG.md` directly. release-please ignores `site/`.

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
