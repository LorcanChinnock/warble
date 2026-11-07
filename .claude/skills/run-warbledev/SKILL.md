---
name: run-warbledev
description: Run, debug and stop WarbleDev through Xcode, keeping exactly one copy running and stopping it when finished. Use whenever you need Warble running to see or check a change, read its logs, set a breakpoint, take a screenshot of the notch, try a preview state, or before a ux-qa pass on Warble, and whenever the user says run, launch, start, try, test it for real or debug the app.
---

# Run WarbleDev

WarbleDev is the dev build of Warble. Run it from Xcode, through the `mcp__plugin_xcode-integration_xcode__*` tools, so you get Xcode's incremental Debug build, its console with every `Logger` line, and lldb. Only one copy may run at a time, and you stop it when you're done, every time.

## The one-copy rule

- The **Warble** scheme's Run pre-action runs `scripts/dev.sh prepare`. It quits every other WarbleDev (another worktree's, an earlier `make run`, a copy Xcode is debugging) and the installed release, and records that the release was running. `make run` goes through the same script. Never launch WarbleDev any other way: no `open …/WarbleDev.app`, no running the executable, no `make bundle` copy.
- Never touch `/Applications/Warble.app` beyond what `scripts/dev.sh` does. It's the copy the user relies on.
- `scripts/dev.sh status` shows what's running. Check it before you start and after you stop.

## Start

1. **Open this checkout's project.** Call `XcodeListWorkspaces`. Use the workspace whose path is the `Warble.xcodeproj` in your current checkout or worktree, never another worktree's. If it isn't listed, call `XcodeOpenWorkspace` with that absolute path, and note that you opened it. Pass its identifier (such as `workspace-7pNMxYHpS1`, not the path, which the run tools reject) as `workspaceIdentifier` to every call below, since other sessions may have their own Warble windows open.
2. **Pick the scheme.** `XcodeSwitchScheme` to `Warble`, and check `activeDestinationDisplayTitle` is `My Mac`; if not, `XcodeSwitchRunDestination` to it.
3. **Build.** `BuildProject`. On failure, read `GetBuildLog` (severity `error`) and fix the code before running. `Warble Dev` signing errors mean `scripts/make-dev-cert.sh` hasn't been run; tell the user rather than signing another way.
4. **Run.** `RunProject`, with `attachDebugger: true` only when you need lldb. It returns once WarbleDev is up. Confirm with `scripts/dev.sh status`: one WarbleDev, running from Xcode's DerivedData.

## While it runs

- **Logs:** `GetConsoleOutput` with a `pattern` and a small `tailLimit`. WarbleDev logs under subsystem `dev.lorcan.Warble.dev`, by category from `Logger.warble("…")`; `includeMetadata: true` shows both, but makes each line long. At launch, system frameworks log errors such as AppIntents failing to reach `com.apple.linkd.autoShortcut`. They aren't Warble's, so don't chase them; a healthy launch ends with `Stream started` and `Ready`.
- **Debugger:** `InvokeDebuggerCommand`. Start with `process status`; prefer `v` and `p` to `po`. Breakpoints you set persist in the shared session, so clear them (`breakpoint delete`) before you hand back. Don't `kill` or `pkill` a copy under the debugger: it pauses in lldb instead of quitting. Use `StopProject`, or `scripts/dev.sh stop`, which ends its `debugserver` first.
- **Preview states** (a track without playing anything, the virtual notch, a pill housing, German): the Warble scheme has these as launch arguments that start off, and `RunProject` can't pass arguments. Use the fallback below with `APP_ARGS`, rather than editing the scheme.
- **Driving the UI** (hover, click, screenshots): hand over to the `ux-qa` skill or computer use, with WarbleDev already running.
- **A code change:** call `RunProject` again. Xcode rebuilds and replaces the running copy, and the pre-action makes sure nothing else is left.

## Stop, always

When you've finished checking, and before you report back, even when something failed part way:

1. `StopProject` for the workspace.
2. `scripts/dev.sh stop`. It quits any WarbleDev still running, clears a leftover adapter process, and reopens the installed Warble if the run quit it.
3. `scripts/dev.sh status` should report no WarbleDev.
4. If you opened the workspace in step 1 of Start, `XcodeCloseWorkspace` it.

Don't leave WarbleDev running for the user unless they ask you to; say so in your report if they did.

## Fallback without the Xcode tools

If the Xcode tools aren't available, or you need launch arguments:

```bash
make run                                        # Debug build into build/DerivedData, then the one-copy launch
make run APP_ARGS='-notchPreviewState resting'  # any of the scheme's preview arguments
/usr/bin/log stream --predicate 'subsystem == "dev.lorcan.Warble.dev"'   # logs; in zsh, plain log is a builtin
make stop                                       # always, when finished
```
