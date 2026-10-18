# Contributing to Warble

Thanks for helping. Bug reports, ideas, and pull requests are all welcome. For a large change, open an issue first so we can agree on the approach.

## Design principle

The default is the simplest state. Extra features start off, and the user turns them on if they want them.

## Set up

You need a Mac with macOS 15 or later, either Xcode or the Xcode Command Line Tools, and [CMake](https://cmake.org) (`brew install cmake`). Warble is a SwiftPM package whose only Swift dependency is [Sparkle](https://sparkle-project.org), for updates. It also bundles [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter), which reads what's playing; `make bundle` builds it with CMake from the `Vendor/mediaremote-adapter` submodule.

```bash
git clone --recurse-submodules https://github.com/LorcanChinnock/warble.git   # in an existing clone: git submodule update --init
cd warble
scripts/make-dev-cert.sh   # once: a stable signing identity, so permissions survive rebuilds
make run                   # build, install to /Applications/WarbleDev.app, and launch
```

macOS ties permissions such as Automation to the app's code signature. An ad-hoc signature changes on every build, so those permissions would reset each time. `make-dev-cert.sh` creates a self-signed certificate named `Warble Dev` in your login keychain, and the build signs with it. Keychain Access shows it as "not trusted"; that's expected and signing still works. To sign with another identity, set `WARBLE_SIGN_IDENTITY`.

Only `make dist` builds `Warble.app` with the update feed. Every other build is `WarbleDev.app`: a separate app with its own bundle ID (`dev.lorcan.Warble.dev`), settings, permissions and `warble-dev://` URL scheme, and no update feed. It installs beside a released Warble rather than over it, and Sparkle never replaces it. Quit a running release first (`pkill -x Warble`), or both draw in the notch.

### Make targets

| Target | What it does |
|---|---|
| `make run` | Build, install to `/Applications/WarbleDev.app`, and launch |
| `make build` | `swift build`, without making an app |
| `make test` | Run the `WarbleModel` and `WarbleCore` unit tests |
| `make test-linux` | Run the `WarbleModel` tests on Linux in Docker, as CI does |
| `make lint` | Check for code patterns that have caused bugs (`scripts/lint.sh`) and, on a Mac, that the string catalog is up to date |
| `make strings` | Add new strings to `Resources/Localizable.xcstrings` and drop unused ones |
| `make app` | Build and install without launching (`INSTALL_DIR=~/Applications make app` to install elsewhere) |
| `make bundle` | Build and sign `build/WarbleDev.app` only |
| `make dist` | Build a universal (Apple Silicon and Intel) `build/Warble.zip`, as the release workflow does |
| `make icon` | Regenerate `Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `make clean` | Remove build output |

**Command Line Tools only:** the CLT's default SDK (27) makes SwiftUI's `@State` a macro whose compiler plugin ships only with Xcode. When Xcode isn't selected, the Makefile pins the newest 26.x SDK the CLT has and points the tests at the CLT's testing plugin, so use `make` rather than a bare `swift build`. With Xcode, nothing is pinned.

### Updating the adapter

Since macOS 15.4, only Apple-signed processes can read what's playing through MediaRemote. MediaRemote Adapter gets round this: Warble runs the adapter's Perl script under `/usr/bin/perl`, which is Apple-signed, and the script loads the adapter's framework. `make bundle` builds the framework and the adapter's test client from the `Vendor/mediaremote-adapter` submodule, puts them and the script in `Contents/Resources`, and signs them with the app's identity. The app never links the framework.

The submodule is pinned to a tagged commit, and Dependabot doesn't update it. To move to a new release of the adapter:

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
5. Open a pull request titled `build(deps): bump mediaremote-adapter to v0.7.8`. CI's `adapter` job runs the same check on macOS 15 and 26.

## Project layout

```
Sources/WarbleModel/    Pure logic that needs only Foundation, tested on Linux: notch geometry
Sources/WarbleCore/     Logic that needs Apple frameworks but no window: preferences
Sources/Warble/         The app: the menu bar menu and updates
Tests/WarbleModelTests/ WarbleModel's Swift Testing suite
Tests/WarbleCoreTests/  WarbleCore's Swift Testing suite
Resources/              Info.plist, the app icon and the string catalog
scripts/                Bundling, install, signing certificate, icon, lint and the Homebrew cask
Vendor/                 MediaRemote Adapter, as a git submodule
docs/                   The roadmap, performance budgets, and images for the README and the user guide
site/                   The website (see site/README.md)
```

If logic can be tested without a window, a display, or a permission, put it in `WarbleModel` and add a test. If it needs an Apple framework, such as Core Audio or AppKit's colour maths, put it in `WarbleCore` instead, keeping the Apple part as thin as you can. CI also runs `WarbleModel`'s tests on Linux, which keeps it portable. `Warble` holds the AppKit and SwiftUI code that needs a real session.

## Strings and translations

Warble's interface is in English, and every string it shows goes through `Resources/Localizable.xcstrings`, so it can be translated. Each build extracts the strings from `Sources/Warble` and `Sources/WarbleCore` (see `Package.swift`), and `make strings` adds the new ones to the catalog. `make lint` and CI fail while the catalog is out of date.

A string reaches the catalog when it's a literal passed to an API that localizes:

- SwiftUI's `Text`, `Button`, `Toggle` and the like. A `String` variable passed to one of these is shown as it is, so a string that needs translating has to be localized where it's defined.
- `String(localized: "…")`, for AppKit titles, alerts, panel messages and any `String` property that holds text the user reads.

Interpolate values into one string, such as `"Playing on \(device)"`, rather than joining fragments, so a translator can reorder the words. Leave log messages and text that scripts read in English.

To add a language, open the catalog in Xcode, add the language, translate each string and add its code to `CFBundleLocalizations` in `Resources/Info.plist`. To try a language without changing your Mac's, run `open -a WarbleDev --args -AppleLanguages '(de)'`.

## Debugging

Warble logs to the unified log under its bundle identifier. File paths are redacted unless you've enabled private data logging.

```bash
/usr/bin/log stream --predicate 'subsystem == "dev.lorcan.Warble.dev"'   # WarbleDev; a release logs under dev.lorcan.Warble
```

## Sending a change

- Keep each pull request focused on one change, and match the style of the surrounding code.
- Every pull request links an issue: put `Closes #N` in its description, or `Part of #N` when it doesn't finish the issue.
- Run `make lint` and `make test`, then run the app and try your change. CI runs the same checks on macOS, and the `WarbleModel` tests on Linux too, but running them first saves a round trip.
- Use a [Conventional Commits](https://www.conventionalcommits.org) title for the pull request, such as `fix(notch): …` or `feat(player): …`. Pull requests are squash-merged, so the title becomes the commit on `main`, and release notes are generated from it.

Everyone taking part in the project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

By contributing, you agree that your contributions are licensed under the project's [GPL-3.0 license](LICENSE).

## Releases

Releases are automated with [release-please](https://github.com/googleapis/release-please). Don't create tags or edit the version by hand.

1. When `main` gets a `feat:` or `fix:` commit, release-please opens or updates a release pull request. It bumps the version in `Resources/Info.plist` and `.release-please-manifest.json`, and adds the changes to `CHANGELOG.md`. While Warble is in beta, each release only bumps the beta number, for example `0.1.0-beta.1` to `0.1.0-beta.2`, whether it has features or only fixes. Changes under `site/` never trigger one. Other types such as `docs`, `chore`, `ci`, `refactor`, and `build` appear in the history but don't trigger a release.
2. The release pull request's CI is the release gate. It runs again on every push to the pull request, and the pull request can't merge until it passes. Once the performance budgets exist ([docs/performance.md](docs/performance.md)), the gate runs them too.
   - A repository admin merges the release pull request by hand. The repository has auto-merge turned off.
   - If the gate fails, fix it in a normal pull request first. release-please only updates the release pull request for changes that appear in the changelog, so after a `test:`, `ci:` or `docs:` fix, run `gh pr update-branch <number>` on the release pull request to run the gate again.
3. The merge tags the release (`v0.1.0-beta.1`, say) and creates a draft GitHub release. The release workflow runs the tests again on the tagged commit, since a commit merged after the gate passed may have changed it. It then builds `Warble-<tag>.zip`, signs it for Sparkle, attaches it with `appcast.xml`, the update feed, and only then publishes the release, so the latest release always has a feed. Installed copies read the feed from the latest release. Last, the workflow rebuilds the website and updates the Homebrew cask.

To force a particular version, add a `Release-As: X.Y.Z` line to the body of a commit on `main`.

### Release secrets

The release workflow needs five secrets, which belong in a GitHub Environment named `release` so no other workflow or branch can read them. Create them once, and keep a backup of each somewhere safe: if you lose the Sparkle key, installed copies can't verify updates and you have to ship a new key by hand.

| Secret | What it is |
|---|---|
| `SPARKLE_PRIVATE_KEY` | The EdDSA key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist`. |
| `WARBLE_SIGNING_CERT_P12` | A base64 `.p12` of the self-signed `Warble Release` code-signing certificate. Every release signs with it, so macOS keeps the permissions it granted across updates. |
| `WARBLE_SIGNING_CERT_PASSWORD` | The password for that `.p12`. |
| `HOMEBREW_TAP_DEPLOY_KEY` | The private half of an SSH deploy key with write access to `LorcanChinnock/homebrew-tap` only. The workflow uses it to update `Casks/warble.rb` there; the tap's `main` ruleset lets deploy keys push. |
| `SITE_DEPLOY_HOOK` | The URL of the website's Cloudflare deploy hook, which rebuilds the site so its download button moves to the new release. See [site/README.md](site/README.md). |

Set the environment up once under Settings › Environments › `release`: limit deployment branches and tags to `main` and `v*`, and store the five secrets there instead of at repository level (`gh secret set --env release NAME`). Add a ruleset for `v*` tags that blocks deletion, updates and non-fast-forward pushes. The release build fails if the `Warble Release` signing identity is missing, rather than signing ad hoc.

release-please opens the release pull request as a GitHub App rather than with the workflow's own token, because GitHub holds the workflows on a pull request from `github-actions[bot]` until someone approves them. Create a private GitHub App once (Settings › Developer settings › GitHub Apps) with no webhook and these repository permissions: Contents, Pull requests and Issues set to read and write. Install it on this repository only. Then store its client ID as a repository variable and a private key as a repository secret. The release-please job runs on every push to `main`, outside the `release` environment, so these two can't live there:

```bash
gh variable set RELEASE_APP_CLIENT_ID                          # paste the app's client ID
gh secret set RELEASE_APP_PRIVATE_KEY < warble-release.private-key.pem
```

Each release also attaches `SHA256SUMS` and a build provenance attestation. To check a direct download, run `shasum -a 256 -c SHA256SUMS` and `gh attestation verify Warble-vX.Y.Z.zip -R LorcanChinnock/warble`.

```bash
make build                                                     # fetches Sparkle's tools
# --account keeps Warble's key apart from other apps' keys in the keychain; without it you get the default account's key.
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account warble     # prints the public key for SUPublicEDKey
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account warble -x sparkle.key
gh secret set --env release SPARKLE_PRIVATE_KEY < sparkle.key

scripts/make-dev-cert.sh "Warble Release" release.p12            # prints the .p12 password
base64 -i release.p12 | gh secret set --env release WARBLE_SIGNING_CERT_P12
gh secret set --env release WARBLE_SIGNING_CERT_PASSWORD         # paste the password

rm sparkle.key release.p12                                     # both stay in your login keychain

ssh-keygen -t ed25519 -N "" -C "warble release workflow" -f tap_key
gh repo deploy-key add tap_key.pub -R LorcanChinnock/homebrew-tap --allow-write --title "warble release workflow"
gh secret set --env release HOMEBREW_TAP_DEPLOY_KEY < tap_key
rm tap_key tap_key.pub                                         # make a new key if you lose it

gh secret set --env release SITE_DEPLOY_HOOK                   # paste the hook URL from Cloudflare
```

Until the website is on Cloudflare, leave `SITE_DEPLOY_HOOK` unset: the release skips the website step and still updates the Homebrew cask.
