# Contributing to Warble

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. For a large change, open an issue first so we can agree on the approach.

## Design principle

The default is the simplest state. Extra features start off, and the user turns them on if they want them.

## Set up

You need a Mac with macOS 15 or later, Xcode 16 or later, and [CMake](https://cmake.org) (`brew install cmake`). Warble is an Xcode project, `Warble.xcodeproj`, whose only Swift dependency is the [Sparkle](https://sparkle-project.org) package, for updates. It also bundles [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter), which reads what's playing; a build phase in the app target builds it with CMake from the `Vendor/mediaremote-adapter` submodule.

```bash
git clone --recurse-submodules https://github.com/LorcanChinnock/warble.git   # in an existing clone: git submodule update --init
cd warble
scripts/make-dev-cert.sh   # once: a stable signing identity, so permissions survive rebuilds
make run                   # build and launch WarbleDev; make stop quits it
```

Or, better for day-to-day work, open `Warble.xcodeproj` in Xcode and press ⌘R, as described in [Working in Xcode](#working-in-xcode).

macOS ties permissions such as Automation to the app's code signature. An ad-hoc signature changes on every build, so those permissions would reset each time. `make-dev-cert.sh` creates a self-signed certificate named `Warble Dev` in your login keychain, and the build signs with it. Keychain Access shows it as "not trusted"; that's expected and signing still works. To sign with another identity, set `WARBLE_SIGN_IDENTITY`.

Only `make dist` builds `Warble.app` with the update feed. Every other build is `WarbleDev.app`: a separate app with its own bundle ID (`dev.lorcan.Warble.dev`), settings and permissions, and no update feed. It runs beside a released Warble rather than replacing it, and Sparkle never updates it.

Only one WarbleDev runs at a time. Xcode's Run and `make run` both go through `scripts/dev.sh`, which first quits every other WarbleDev, whether from another worktree, an earlier run or a copy Xcode is debugging. It also quits the installed Warble, since both draw in the notch, and `make stop` reopens it.

### Make targets

| Target | What it does |
|---|---|
| `make run` | A Debug build, as Xcode's Run makes, launched from `build/DerivedData` after quitting every other WarbleDev (`APP_ARGS='-notchPreviewState resting'` passes launch arguments) |
| `make stop` | Quit WarbleDev, however it started, and reopen the installed Warble if a run quit it |
| `make build` | A Debug build of the app, the same as Xcode's Build |
| `make test` | Run the `WarbleModel` and `WarbleCore` unit tests (`ONLY='WarbleModelTests/notchSitsBetweenTheMenuBarAreas()'` runs one) |
| `make test-linux` | Run the `WarbleModel` tests on Linux in Docker, as CI does |
| `make coverage` | Print line coverage per file for `WarbleModel` and `WarbleCore` ([docs/coverage.md](docs/coverage.md)) |
| `make perf` | Time the paths with a performance budget ([docs/performance.md](docs/performance.md)) |
| `make lint` | Check for code patterns that have caused bugs (`scripts/lint.sh`) and, on a Mac, that the string catalog is up to date |
| `make strings` | Add new strings to `Resources/Localizable.xcstrings` and drop unused ones |
| `make bundle` | Archive a universal Release `build/WarbleDev.app`, as Product › Archive does, and keep the archive with its dSYMs |
| `make dist` | Build a universal (Apple Silicon and Intel) `build/Warble.zip`, as the release workflow does |
| `make icon` | Regenerate the app icon in `Resources/Assets.xcassets` from `scripts/make-icon.swift`. Its bars come from `Sources/WarbleModel/Design/IconBars.swift`, which the menu bar icon draws too |
| `make clean` | Remove build output |

### Working in Xcode

Open `Warble.xcodeproj`. Pick the **Warble** scheme and **My Mac**, then press ⌘R to build WarbleDev and run it with the debugger attached, or ⌘U to run the tests in `Tests/Warble.xctestplan`. Breakpoints, the console and SwiftUI previews all work, and the copy Xcode runs has the adapter, so it shows what's playing. Run `scripts/make-dev-cert.sh` first, as above: the project signs with `Warble Dev`, and the build fails without it.

- **Settings** live in `Config/*.xcconfig`, never in the project file. `Shared.xcconfig` has the version, signing and Swift settings, `Debug.xcconfig` and `Release.xcconfig` the configurations, and each target has its own file. For a setting only you need, such as another signing identity, create `Config/Local.xcconfig`, which git ignores, and set it there: `CODE_SIGN_IDENTITY = Apple Development`, say.
- **New files** need no project edit. The targets use synchronised folders, so a Swift file added under `Sources/Warble`, `Sources/WarbleCore`, `Sources/WarbleModel` or either test folder is part of that target.
- **WarbleDev or Warble.** Every build is WarbleDev, Xcode's included. `Config/Warble.xcconfig` builds Warble, with the update feed, only when `WARBLE_DISTRIBUTION=YES`, which only `make dist` passes.
- **Run quits every other WarbleDev and the installed Warble** first, through the scheme's pre-action (`scripts/dev.sh prepare`), because each draws in the notch and their panels would stack. Stop (⌘.) ends the run; `make stop` then reopens the installed Warble if Run quit it.
- **Preview states.** The scheme's Run arguments include `-notchPreviewState resting`, `-notchPreviewVirtual YES`, `-notchPreviewHousing pill` and `-AppleLanguages (de)`, all off. Tick one in Product › Scheme › Edit Scheme › Run › Arguments to try it, and untick it before you commit.
- **The performance budgets** run only from the **Perf** test plan, which sets `WARBLE_PERF`. Pick it in the scheme's test plans, or run `make perf`.

The Makefile builds the same project through `scripts/xcodebuild.sh`, into `build/DerivedData` rather than Xcode's own folder: Xcode 27 can leave a test bundle unsigned when the IDE and `xcodebuild` share one. CI and the release workflow run the same `make` targets. `Package.swift` holds only WarbleModel and its tests, so `make test-linux` and CI's `linux` check can build them on Linux.

### Updating the adapter

Since macOS 15.4, only Apple-signed processes can read what's playing through MediaRemote. MediaRemote Adapter gets round this: Warble runs the adapter's Perl script under `/usr/bin/perl`, which is Apple-signed, and the script loads the adapter's framework. The app target's **Build the adapter** phase builds the framework and the adapter's test client from the `Vendor/mediaremote-adapter` submodule with CMake, puts them and the script in `Contents/Resources`, and signs them with the app's identity, so every build has them, Xcode's included. The app never links the framework.

The submodule is pinned to a tagged commit. Dependabot checks it weekly, but it follows the adapter's `main` branch, not its tags, so its pull request may point at an untagged commit. If the new commit is a release, check it as in step 4 and merge. Otherwise close the pull request, or move to a tag by hand:

1. Read the [adapter's releases](https://github.com/ungive/mediaremote-adapter/releases) for changes to its commands or JSON output.
2. Check out the new tag in the submodule, then stage it:
   ```bash
   git -C Vendor/mediaremote-adapter fetch --tags
   git -C Vendor/mediaremote-adapter checkout v0.7.8   # the new tag
   git add Vendor/mediaremote-adapter
   ```
3. If the adapter's `LICENSE` changed, update its section in `Resources/Acknowledgements.txt`.
4. Run `make bundle`, then check the adapter still works. An exit code of 0 means it does:
   ```bash
   r="$PWD/build/WarbleDev.app/Contents/Resources"
   /usr/bin/perl "$r/mediaremote-adapter.pl" "$r/MediaRemoteAdapter.framework" "$r/MediaRemoteAdapterTestClient" test; echo $?
   ```
   If the release notes change the `stream` output, play something in Safari, record a few lines with `stream --micros` in place of `test`, and update the fixtures in `Tests/WarbleModelTests/Fixtures`, which `make test` replays. Swap each `artworkData` value for a short stand-in, as the existing files do.
5. Open a pull request titled `build(deps): bump mediaremote-adapter to v0.7.8`. CI's `adapter` job runs the same check on macOS 15 and 26.

## Project layout

```
Sources/WarbleModel/    Pure logic that needs only Foundation, tested on Linux: the app's state and reduce (App/), and each feature's rules
Sources/WarbleCore/     Logic that needs Apple frameworks but no window: the sources, Core Audio
Sources/Warble/         The app: the composition root (App/), the notch, Settings, the menu bar menu and updates
Tests/WarbleModelTests/ WarbleModel's Swift Testing suite, in the same folders, with the ports' fakes in App/Fakes.swift
Tests/WarbleCoreTests/  WarbleCore's Swift Testing suite
Tests/*.xctestplan      The test plans the Warble scheme runs: Warble (the default) and Perf (the budgets)
Resources/              Info.plist, the entitlements, the asset catalog with the app icon, and the string catalogs
Config/                 The build settings (.xcconfig files) for every target
Warble.xcodeproj        The project: the Warble, WarbleCore, WarbleModel and test targets, and their shared schemes
Package.swift           WarbleModel and its tests alone, for the Linux build
scripts/                Building, bundling, install, signing certificate, icon, lint, and the install and uninstall tests
Vendor/                 MediaRemote Adapter, as a git submodule
docs/                   Per-feature architecture notes (architecture/), performance budgets, images for the README and the user guide, and demo/, a made-up player to record
site/                   The website (see site/README.md)
```

If logic can be tested without a window, a display, or a permission, put it in `WarbleModel` and add a test. If it needs an Apple framework, such as Core Audio or AppKit's colour maths, put it in `WarbleCore` instead, keeping the Apple part as thin as you can. CI also runs `WarbleModel`'s tests on Linux, which keeps it portable. `Warble` holds the AppKit and SwiftUI code that needs a real session.

Each target is split into feature folders: `App`, `Playback`, `Notch`, `Idle`, `Keys`, `Displays`, `Volume`, `Design` and `Settings`.

## Adding a feature

Everything the app decides goes through one store. `AppState` holds it, `AppAction` is what can happen, and `reduce(_:_:now:)` in `Sources/WarbleModel/App` turns an action into the next state and a list of `AppEffect`s, the work to do outside it. `Store` runs it on the main actor and keeps one timer for the state's earliest deadline. A new feature adds files rather than growing a central class:

1. **State.** Add what the feature decides to `AppState`, or a struct of its own inside it. If it waits for something, take timestamped events and return the next deadline rather than running a timer, as `HoverIntent` and `IdleAfterPause` do, and include that deadline in `AppState.deadline`. With nothing playing there must be none.
2. **Actions.** Add an `AppAction` case for each thing that can happen: a click, a key, an answer from slow work. Handle it in `reduce`. If it changes what follows from the notches' states, the settle pass at the end of `reduce` is where that goes.
3. **Effects.** Add an `AppEffect` case for each piece of work outside the state, such as sending a command or saving a file. `EffectRunner` carries out the ones that go through a port, and `PlatformEffects` (`Sources/Warble/App`) the ones that need AppKit. Slow work runs off the main actor and comes back as an action.
4. **Ports.** If the runner needs something new from the Mac, add a protocol to `App/Ports.swift` with the real implementation in WarbleCore or the app and a fake in `Tests/WarbleModelTests/App/Fakes.swift`. Add one only when a test needs the fake.
5. **Folders.** Put the feature's files in a folder of its name in each target that has any, and its tests in the same folder under `Tests/WarbleModelTests`.
6. **Views.** Views draw state and dispatch actions; they decide nothing. A view gets Warble's objects from the SwiftUI environment, never from a shared instance, and `AppEnvironment` builds them once.
7. **Tests.** Test the feature through `reduce` and, for its effects, `EffectRunner` with fakes. Both run on Linux. Check what it does with nothing playing too.

Anything on the hover, expand or play/pause path that lives in WarbleModel or WarbleCore adds a budget to `Tests/WarbleCoreTests/PerfTests.swift` and `docs/performance.md`, and its PR gets the `performance` label so CI runs the budgets. Changes on those paths in the app target, which `PerfTests` can't reach, are checked with the `Expand` and `Play/pause` signposts instead ([performance note](docs/architecture/performance.md)).

Each feature has a note in [docs/architecture](docs/architecture), listed in CLAUDE.md. Read the one for the feature you change, and update it in the same pull request.

Nothing may sit between a hover or a click and the panel: dispatch is synchronous, with no `Task` hop, Combine or async/await on that path. A command's guess shows at once; the command itself goes to the player afterwards as an effect.

## Strings and translations

Warble's interface is in English, German, Spanish, French, Italian, Japanese, Korean, Brazilian Portuguese and Simplified Chinese. Every string it shows goes through `Resources/Localizable.xcstrings`, so it can be translated. Each build extracts the strings from `Sources/Warble` and `Sources/WarbleCore`. Building in Xcode adds the new ones to the catalog, since the catalog belongs to both targets, and `make strings` does the same from the terminal. `make lint` and CI fail while the catalog is out of date.

A string reaches the catalog when it's a literal passed to an API that localizes:

- SwiftUI's `Text`, `Button`, `Toggle` and the like. A `String` variable passed to one of these is shown as it is, so a string that needs translating has to be localized where it's defined.
- `String(localized: "…")`, for AppKit titles, alerts, panel messages and any `String` property that holds text the user reads.

Interpolate values into one string, such as `"Playing on \(device)"`, rather than joining fragments, so a translator can reorder the words. Leave log messages and text that scripts read in English.

A new string needs a translation in each language, and `make strings` adds it untranslated, so translate it before you merge. The two permission prompts in `Resources/Info.plist` are translated in `Resources/InfoPlist.xcstrings`. To add a language, open both catalogs in Xcode, add the language, translate each string and add its code to `CFBundleLocalizations` in `Resources/Info.plist`. To try a language without changing your Mac's, turn on `-AppleLanguages (de)` in the scheme's Run arguments, or run `make run APP_ARGS="-AppleLanguages '(de)'"`.

## Debugging

Warble logs to the unified log under its bundle identifier. File paths are redacted unless you've enabled private data logging.

```bash
/usr/bin/log stream --predicate 'subsystem == "dev.lorcan.Warble.dev"'   # WarbleDev; a release logs under dev.lorcan.Warble
```

## Sending a change

- Keep each pull request focused on one change, and match the style of the surrounding code.
- Every pull request links an issue: put `Closes #N` in its description, or `Part of #N` when it doesn't finish the issue.
- Run `make lint` and `make test`, then run the app and try your change. CI runs the same checks on macOS, and the `WarbleModel` tests on Linux too, but running them first saves a round trip.
- If your change could slow the notch opening, play/pause, a track change, or wake Warble while nothing is playing, run `make perf`, and label the pull request `performance` so CI runs the budgets too. [docs/performance.md](docs/performance.md) has the budgets and what each one measures.
- Use a [Conventional Commits](https://www.conventionalcommits.org) title for the pull request, such as `fix(notch): …` or `feat(player): …`. Pull requests are squash-merged, so the title becomes the commit on `main`, and release notes are generated from it.
- Use `site: …` for website changes (the Astro site and the user guide in `site/`). release-please ignores that type, so it makes no changelog entry and no new app version. If the same change also alters what the app does, split it, and give the app change its own `fix:` or `feat:` title.

Everyone taking part in the project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).

## Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please). Don't create tags or edit the version by hand.

1. When `main` gets a `feat:` or `fix:` commit, release-please opens or updates a release pull request. It bumps `MARKETING_VERSION` in `Config/Shared.xcconfig` and `.release-please-manifest.json`, and adds the changes to `CHANGELOG.md`. While Warble is in beta, each release only bumps the beta number, for example `0.1.0-beta.1` to `0.1.0-beta.2`, whether it has features or only fixes. Changes under `site/` never trigger one. Other types such as `docs`, `chore`, `ci`, `refactor`, and `build` appear in the history but don't trigger a release.
2. The release pull request's CI is the release gate. It runs again on every push to the pull request, and the pull request can't merge until it passes. The gate runs the performance budgets too ([docs/performance.md](docs/performance.md)).
   - A repository admin merges the release pull request by hand. The repository has auto-merge turned off.
   - If the gate fails, fix it in a normal pull request first. release-please only updates the release pull request for changes that appear in the changelog, so after a `test:`, `ci:` or `docs:` fix, run `gh pr update-branch <number>` on the release pull request to run the gate again.
3. The merge tags the release (`v0.1.0-beta.1`, say) and creates a draft GitHub release. The release workflow runs the tests again on the tagged commit, since a commit merged after the gate passed may have changed it. It then builds `Warble-<tag>.zip`, signs it for Sparkle, attaches it with `appcast.xml`, the update feed, and only then publishes the release, so the latest release always has a feed. Installed copies read the feed from the latest release. Last, the workflow rebuilds the website. `site/public/install.sh`, the command on the download page, reads the latest release's `SHA256SUMS` and zip, so it needs no change per release. `site/public/uninstall.sh` removes what Warble keeps on a Mac, so add any new folder Warble writes to it and to the Remove Warble guide.

To force a particular version, add a `Release-As: X.Y.Z` line to the body of a commit on `main`.

### Release secrets

The release workflow needs three secrets, which belong in a GitHub Environment named `release` so no other workflow or branch can read them. Create them once, and keep a backup of each somewhere safe: if you lose the Sparkle key, installed copies can't verify updates and you have to ship a new key by hand.

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist`. |
| `WARBLE_SIGNING_CERT_P12` | A base64 `.p12` of the self-signed `Warble Release` code-signing certificate. Every release signs with it, so macOS keeps the permissions it granted across updates. |
| `WARBLE_SIGNING_CERT_PASSWORD` | The password for that `.p12`. |

Set the environment up once under Settings › Environments › `release`: limit deployment branches and tags to `main` and `v*`, and store the three secrets there instead of at repository level (`gh secret set --env release NAME`). Add a ruleset for `v*` tags that blocks deletion, updates and non-fast-forward pushes. The release build fails if the `Warble Release` signing identity is missing, rather than signing ad hoc.

release-please opens the release pull request as a GitHub App rather than with the workflow's own token, because GitHub holds the workflows on a pull request from `github-actions[bot]` until someone approves them. Create a private GitHub App once (Settings › Developer settings › GitHub Apps) with no webhook and these repository permissions: Contents, Pull requests and Issues set to read and write. Install it on this repository only. Then store its client ID as a repository variable and a private key as a repository secret. The release-please job runs on every push to `main`, outside the `release` environment, so these two can't live there:

```bash
gh variable set RELEASE_APP_CLIENT_ID                          # paste the app's client ID
gh secret set RELEASE_APP_PRIVATE_KEY < warble-release.private-key.pem
```

Each release also attaches `SHA256SUMS` and a build provenance attestation. To check a direct download, run `shasum -a 256 -c SHA256SUMS` and `gh attestation verify Warble-vX.Y.Z.zip -R LorcanChinnock/warble`.

```bash
make build                                                     # fetches Sparkle's tools
# --account keeps Warble's key apart from other apps' keys in the keychain; without it you get the default account's key.
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account warble     # prints the public key for SUPublicEDKey
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account warble -x sparkle.key
gh secret set --env release SPARKLE_PRIVATE_KEY < sparkle.key

scripts/make-dev-cert.sh "Warble Release" release.p12            # prints the .p12 password
base64 -i release.p12 | gh secret set --env release WARBLE_SIGNING_CERT_P12
gh secret set --env release WARBLE_SIGNING_CERT_PASSWORD         # paste the password

rm sparkle.key release.p12                                     # both stay in your login keychain

```
