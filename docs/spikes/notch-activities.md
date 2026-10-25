# Spike: notch activities protocol

Design for [#50](https://github.com/LorcanChinnock/warble/issues/50), the first step of [#49](https://github.com/LorcanChinnock/warble/issues/49). Nothing is built. [#51](https://github.com/LorcanChinnock/warble/issues/51) builds it from this page.

An activity is a short live thing another Mac app shows in the notch, the way Warble shows music. The first user is Shot's recording timer: a red dot on the left, `00:42` on the right, and a Stop button when you open the notch.

## Answer

Another app asks over a second Unix socket, `activities.sock`, next to the command line's. The app keeps one connection open for as long as its activity lives, sends JSON lines to start it, change it and end it, and gets button presses back on the same connection. Closing the connection ends the activity, so a crashed app never leaves a timer behind. The socket exists only while Settings › Activities is on, which starts off.

An activity takes the resting notch's wings from music and from the Doctor's "!" while it lives, and never anything else. Hovering or clicking still opens the player, so play/pause is never behind an activity. It lasts until its sender ends it, the connection closes, the user dismisses it or its `lasts` runs out, one hour by default and twelve at most.

It's built as two pull requests: the model and the drawing first, then the socket with its Settings card and guide.

## The transport

| | Tells who is asking | Knows when the sender is gone | Can send a button press back | Works from a script | Costs when off |
| --- | --- | --- | --- | --- | --- |
| **Unix socket** | Yes, from the connection | Yes, the connection closes | Yes, on the same connection | Yes (`nc -U`, any language) | Nothing, no socket exists |
| `warble://` link | No | No | No | Yes | Nothing |
| Swift package | Only as far as it wraps a socket | Only as far as it wraps a socket | Only as far as it wraps a socket | No | Nothing |
| XPC or Mach service | Yes | Yes | Yes | No | A service name to register |
| Distributed notifications | No | No | One-way broadcast to every app | Awkward | Every app hears it |

The socket is the only one that gets all four things an activity needs. A link is one-way and fire-and-forget, so it can't say who sent it, end by itself when the sender dies, or take a button press back. A link would suit a "show this for four seconds" notice, but that isn't what #49 asks for, and it can be added later without changing anything here. XPC would work for Swift senders but needs a registered Mach service name, which an app that isn't launched by launchd can't get, and it's no use to a shell script. Distributed notifications reach every app on the Mac.

A Swift package is a wrapper, not a transport. Don't build one now. The client is about eighty lines, and Shot can carry its own. The example in #51 is that client as a single script (see [Example and guide](#example-and-guide)). If a second Swift sender asks for a package, it's one over this protocol.

### Why not the command line's socket

[`agent.sock`](../architecture/developer.md) answers one request and closes. An activity needs the connection to stay, for its lifetime and for the button press coming back. The command line's socket also follows a different switch (Settings › Developer, for people who script Warble). Someone who wants Shot's timer in the notch shouldn't have to turn on a developer feature, and turning on the command line shouldn't let every app on the Mac put things in the notch.

So `activities.sock` is a sibling, in the same folder (0700), at mode 0600, with the same-user check on each peer. `AgentSocket` already has that code. #51 pulls the shared parts (`address(of:)`, `peerUser` and the socket setup) out into a small `UnixSocket` helper in the same pull request that adds the server, and `AgentSocket` calls it too. `activities.sock` doesn't share `readLine`. That reads one line and drops what follows it in the chunk, and times out after five seconds, which suits a request and not a connection that stays quiet for hours. The activity server keeps a buffer for each connection that holds the bytes after a newline, so two lines in one read are both answered in order, and it has no idle timeout, only a bound on how long a half-received line may take. `RemoteSocketPath` stays in WarbleModel, where the command line reads it, and gains the `activities.sock` path beside `agent.sock`. No behaviour of the command line changes, and its tests keep passing.

The sandbox is a limit. A sandboxed app can't connect to a socket in another app's Application Support folder, so v1 serves unsandboxed apps and scripts. Shot isn't sandboxed. If a sandboxed sender turns up, the answer is an App Group folder for the socket, which needs a team ID Warble's signing doesn't have today, so it's not planned.

## The protocol

One JSON object per line, UTF-8, newline-terminated, in both directions. A line is at most 4 KB. Every message has `"v": 1`. Warble refuses another version with an error naming the one it speaks, as `RemoteRequest` does.

### From the app

```json
{"v":1,"op":"start","id":"recording","title":"Recording Display 1","detail":"Saves to Desktop",
 "icon":{"symbol":"record.circle","tint":"red"},"clock":{"since":1766592000.0},
 "buttons":[{"id":"stop","label":"Stop","symbol":"stop.fill"}],"priority":"normal","lasts":3600}
{"v":1,"op":"update","id":"recording","detail":"Paused","clock":null}
{"v":1,"op":"end","id":"recording"}
```

| Field | Meaning | Limit |
| --- | --- | --- |
| `id` | The app's name for the activity. Unique within the connection. | 64 bytes |
| `title` | What the card says and VoiceOver reads. | 60 characters |
| `detail` | An optional second line on the card. | 100 characters |
| `badge` | Short text for the right wing when there's no clock. | 8 characters |
| `icon` | `{"symbol": "<SF Symbol name>", "tint": "<colour>"}`, drawn as a badge on the sender's own icon. Omitted, no badge. Tints are `white` (default), `red`, `orange`, `yellow`, `green` and `blue`. No images: nothing here reads a file. | Name: lowercase letters, digits and dots, 64 bytes |
| `clock` | `{"since": t}` counts up from `t`, `{"until": t}` counts down to it, with `t` in seconds since 1970. A clock reaching zero stays at `0:00` until the sender ends the activity. | One of the two |
| `buttons` | Up to two, each `{"id", "label", "symbol"?}`. | Id 32 bytes, label 16 characters |
| `from` | For a script only: the name to show, as "Script: <name>". A signed app's name comes from its signature, so `from` is ignored there. | 30 characters, required for a script |
| `priority` | `normal` or `high`. | Two levels, so senders can't outbid each other |
| `lasts` | Seconds from this message until Warble ends the activity itself. Counted again from each `update` that sets it. | 1 to 43200, default 3600 |

`update` changes only the fields it names, is checked against the same limits as a `start`, and clears a field set to `null`, but only `detail`, `badge`, `clock`, `icon` and `buttons`. `lasts: null` puts it back to the default, so no activity is ever without an end. `title`, `from` and `priority` can't be cleared, and an `update` that tries is refused. `start` with an `id` already in use replaces that activity.

A symbol name Warble can't draw is left off, with the sender's icon alone. The view checks that, since the model can't. A string over its limit is refused, not cut, so a developer sees the mistake instead of a half sentence in the notch.

### From Warble

Each request gets one reply line, in order: `{"v":1,"re":"start","ok":true}` or `{"v":1,"re":"start","ok":false,"error":"…"}`. Errors are sentences, with no codes: `"title is 74 characters; the most is 60"`, `"a connection can have 2 activities at once"`.

Warble also sends events, which carry `event` in place of `re`:

```json
{"v":1,"event":"button","id":"recording","button":"stop"}
{"v":1,"event":"ended","id":"recording","reason":"dismissed"}
```

The `ended` reasons are `dismissed` (the user closed it), `expired` (`lasts` ran out), and `blocked` (the user turned that app off in Settings). An activity the app ends or replaces itself, or one that goes with a closed connection, sends nothing, since the sender already knows. Setting Activities off closes the socket, which every sender sees as a closed connection.

### Limits

Three activities at once across all apps, two for one connection. A connection may send 20 lines a second. This is counted from each line's arrival time, not with a timer, and a line over the rate gets `"error": "slow down"`. A clock needs no updates at all, since Warble draws it from `since` or `until`.

When the socket isn't there, the setting is off or Warble isn't running, and the app shows nothing and says nothing. Connecting is the whole check, so a sender never polls.

## Permissions

macOS shows no prompt for a Unix socket, so Warble's own switch is the permission. Settings › Activities starts off, and nothing listens until it's on. There's no macOS permission to ask for.

Turning it on lets any process of the same user put an activity in the notch. That's no more than it can already do, but the text is the sender's. So Warble doesn't take the sender's word for who it is.

- The sender is the process on the other end of the connection. Warble reads its audit token once, at connect, with `LOCAL_PEERTOKEN`, which names that process and not a process ID that could be reused, and checks its code signature (`SecCodeCopyGuestWithAttributes` on the token). A signed sender is known by its team ID and signing identifier, and its name and icon come from the app that signature belongs to. Another process can't take that identity without the signing key, whatever its `Info.plist` says.
- A script isn't the process on the other end: its sender is the interpreter, which for `nc -U`, `osascript`, `python3` and `swift` is a program with no app behind it. So a sender counts as a signed app only if its executable is inside a top-level `.app` bundle, one not nested in another bundle's `Resources` or `Frameworks`, and signed with a team ID. An interpreter that execs into a helper app, such as python.org's `Python.app` inside its framework, fails the first test, and a short list of interpreter bundle identifiers (`org.python.python` to start) is treated as scripts as well, for any that get past it. The classification is a label for the person reading the card, not a security boundary: a script mistaken for an app still shows under the interpreter's own name, never as another app, since taking an app's identity needs its signing key. Anything else is a script, whatever its signature: Apple's tools, a Developer ID signed `python3` or `node` from an installer, unsigned programs and ad hoc builds. They're allowed, but a script names itself with `from` in `start`, which is shown as "Script: <name>" in the card and in Settings, so nothing appears as a signed app. Such a sender is keyed by its executable's path and `from` together, so blocking one script doesn't block every script on the same interpreter, and two scripts can pick the same `from` only by sharing a block. The label is the guarantee, since the name is the script's own word.
- The wing always draws the sender's real icon: the signed app's, or a generic script mark for a script. A sender's own symbol is only a small badge on it, so no sender can make wings that look like another app's. The card names the sender above the title. A sender can choose a symbol but never the name or icon it appears under.
- An activity can't do anything on the Mac. A button sends one event back to the app that made it, and nothing else: no links open, no commands run.
- Settings › Activities lists each app that has shown an activity, with a switch. Apps are on when they first appear, since turning the feature on was the consent, and turning one off ends its activities with `blocked` and refuses its next `start`. Asking per app in the notch was considered and rejected: a prompt that appears over whatever you're doing isn't calm. If people report unwanted senders, revisit it as a one-time "Allow" button on that app's first activity.

The list of apps is stored as a dictionary of sender key to name under a new `PreferenceKey.activityApps`, and the turned-off ones as a set of keys under `PreferenceKey.activityBlocked`. A signed sender's key is its team ID and signing identifier, so one app can't block another by claiming its bundle ID, and the key of any script, as described above, is its executable's path and `from` together.

## What it shows

A resting notch with an activity draws the sender's icon in the left wing, with the activity's own symbol as a badge on it, and its clock, or its `badge`, in the right. The clock is SwiftUI's `Text(timerInterval:countsDown:)`, which the system ticks, so Warble starts no timer to draw it. It does mean one redraw a second while a clock shows, so it's the one cost to check by hand ([Performance](#performance)).

The expanded notch has two cases:

- **Music is playing.** The player's card and the lyrics card grow by a row below their controls for each activity: an icon and title, the clock, any buttons and a close button. The player stays one hover away.
- **Nothing is playing.** A card of its own, the activity rows only, the height of the idle card plus a row for each extra activity.

A button press dispatches `.activityButton`, and `reduce` asks for `.haptic` along with the event, so there's feedback before the sender answers. The sender is expected to `update` or `end` in reply. Warble doesn't guess what a button does. The close button is always there, so no activity traps the user.

VoiceOver reads the wing as "App name: title, clock" with the clock as its value, each button by its label, and the close button as "Close". The cards' text follows Settings › General › Text size, as the Doctor card's does, and their height stays fixed. With Reduce Motion the wings change at once and only the content fades, the same rule as the other states.

The two things an activity leaves alone: it never takes the key or the keyboard, and it never moves the pointer's state. A notch under the pointer stays where it is when an activity starts.

## Priority against music

One rule: an activity takes the resting wings and, with nothing playing, the card behind them. Open cards keep their content and gain the activity rows, and everything else stays as it is.

| When an activity is live and… | The notch |
| --- | --- |
| music plays, the notch is resting | Draws the activity in the wings. The music's art and bars aren't drawn. |
| music plays, the pointer opens it | The player, with the activity row. |
| nothing plays | Draws the activity in the wings, where it would draw nothing, or an idle housing, or the Doctor's "!". |
| a track-change toast or lyric line is due | Doesn't draw it. The toast's own deadline still runs out, so it's skipped, not held. |
| the Doctor's card is open | That card, as now. |
| the lyrics card is open | That card, with the activity rows below it. |
| a display shows a full-screen app | Hidden, as music is. Not even `toastsInFullScreen` lets it through, so a recording timer never draws over what you're recording. |
| the screen is shared, with "hide from capture" on | Left out of the recording, as the rest of the notch is. |

A failed Doctor check gives way to a live activity on the wings and in the card, and comes back when the activity ends. An activity is short and the user asked for it, while the failure stays until it's fixed, and the card the user needs while recording is the one with Stop on it.

Two activities show one at a time: `high` first, then the newest start. A second activity's wing doesn't cycle. The card lists all of them.

Why music yields the wings: an activity is something you started and want to watch, such as a recording, and it ends. The music keeps playing and returns when the activity does. Why it yields nothing more: the player's card is how you pause it, and nothing may slow that.

## How it fits the store

Following CONTRIBUTING.md › Adding a feature. Files go in `Activities/` in WarbleModel, with the socket in `Activities/` in WarbleCore and the views in `Sources/Warble/Activities/`.

### State

`ActivityState` (WarbleModel, `Activities/`) is a `Feature` in `AppState.activities`, like `ToastState`.

```swift
struct ActivityState: Feature {
    var isOn: Bool                          // PreferenceKey.activities
    var blocked: Set<String>                // PreferenceKey.activityBlocked
    var apps: [String: String]              // identifier → name, for Settings' list
    var items: [Activity]                   // newest start last, at most 3
    var deadline: Date? { items.compactMap(\.endsAt).min() }
    var current: Activity?                  // high first, then the newest start
}
```

`Activity` holds the validated fields above, its `ActivityKey` (the connection's number and the app's `id`), its owner (`ActivityOwner`: identifier and name, read from the connection) and `endsAt`, the start or last update plus `lasts`. `AppState.deadline` gets one more key path, `\.activities.deadline`, so `Store` still arms one timer. With nothing live it's `nil`, and with the setting off `items` is empty. Between start and `endsAt` there's one timer, an hour away by default and twelve at most, and no wakeups, and `reduce` removes the activity on the `.tick` that timer sends.

`SharedState` gains `hasActivity: Bool`, so `Notches` reads whether one is live without knowing its fields. `AppState.listensForActivities` follows the setting, and `settle` asks for the socket once each time it changes, as it does for the command line.

### Actions

| Action | From | Does |
| --- | --- | --- |
| `.activitiesChanged(Bool)` | Settings | Sets `isOn`. Off, it drops every activity, with no events: the socket closes. |
| `.activityBlocklistChanged(Set<String>)` | Settings | Replaces `blocked`, ends each blocked app's activities with `blocked`. |
| `.activityStarted(Activity)` | The socket | Adds the activity, or replaces one with its key, and adds a sender it hasn't seen to `apps`. Ignored while `isOn` is off, for a blocked owner or past the limits. |
| `.activityUpdated(ActivityKey, ActivityPatch)` | The socket | Changes the named fields and restarts `lasts` if it's set. |
| `.activityEnded(ActivityKey)` | The socket | Removes it, sending nothing back. |
| `.activityClientClosed(client: Int)` | The socket | Removes everything the connection started. |
| `.activityButton(ActivityKey, button: String)` | The card | Asks for the event and a haptic, if the activity and the button exist. |
| `.activityDismissed(ActivityKey)` | The card | Removes it and tells the sender. |
| `.tick` | `Store` | Removes each activity past `endsAt` and tells its sender. |

The socket's handler, `ActivityHandler` (WarbleModel, `@MainActor`, like `RemoteHandler`), parses a line into an `ActivityRequest`, checks it against the limits (all in pure functions that run on Linux, so every message in the table above has a test), answers it and dispatches the matching action. `reduce` is the second check: it enforces `isOn`, `blocked` and the counts itself, so an action that gets past the handler can't break a rule. Dispatch is synchronous on the main actor, as for the command line.

### Effects

| Effect | Asked when | Carried out by |
| --- | --- | --- |
| `.listenForActivities(Bool)` | `listensForActivities` changes | `PlatformEffects` opens or closes the socket, like `.listenForCommands`. |
| `.saveActivityApps([String: String])` | `.activityStarted` adds a sender to `apps` | `PlatformEffects` writes `PreferenceKey.activityApps`, as `.turnOffWaveform` writes `PreferenceKey.waveform`. Settings reads it back. |
| `.sendActivityEvent(ActivityKey, ActivityEvent)` | A button press, a dismissal, an expiry or a block | `EffectRunner`, through the `ActivityChannel` port. |

`ActivityEvent` is `.button(String)` or `.ended(reason)`. `.haptic` is asked on a button press too, the effect that exists already.

`ActivityChannel` is the one new port (`send(_:to:)`, writing a line to the connection with that number). It earns one because the bug worth a test is a press reaching the wrong connection or one that has closed, and a fake lets `EffectRunner` tests check both on Linux. The real one is the socket server in WarbleCore. A write to a closed connection is dropped, and the server has already sent `.activityClientClosed`.

### Drawing

`NotchState` gains `activity`, drawn at the size of `resting`. `NotchLayout.frame` and `hoverArea` give it `resting`'s frame and the housing, so a pointer crossing the wings doesn't open it. `NotchState.init` gains `showsActivity`: it's checked before the `idleHover == .nothing` branch and counts like `isPlaying` and `needsAttention`, so a live activity follows `hover` whatever the Idle setting says. A resting notch that would draw `.resting`, `.toast`, `.lyrics`, `.idle` or `.hidden` draws `.activity` instead, and an opened one draws `.expanded`, so the pointer reaches the card, its buttons and its close button with Idle hover set to Nothing too. `Notches.notchState` passes `shared.hasActivity` to it, and `showsToast` and `showsLyrics` are false while one shows, which is how the toast and the lyric line give way.

`NotchCard` gains `activity`. `NotchCard.init` gains `showsActivity`, and the order is the Doctor if asked for, the lyrics, the player while music plays, the activity, the Doctor on a failed check, then the idle card. `NotchLayout.drop` gives the card the idle card's height for one row and a row more for each extra, and the player's card and the lyrics card grow by a row for each activity and draw those rows below their controls, so the lyrics button stays under the pointer when the player's does.

`drawsBars` doesn't count `.activity`, so the live waveform's audio tap stops while an activity covers the bars, and nothing else about the waveform changes.

The views in `Sources/Warble/Activities/` draw `AppState.activities` and dispatch `.activityButton` and `.activityDismissed`. They decide nothing.

### With nothing playing

Nothing playing and no activity: no socket if the setting is off, otherwise a listening socket and no timer, no draw and no CPU, so the mantra holds. An activity is the one thing that makes the notch draw with nothing playing, and only because a person turned the setting on and an app asked.

## Settings and wording

A new section, Settings › Activities, because the people who need it aren't developers: they use an app that offers it. It's not under Developer.

- **Switch:** "Show what other apps are doing in the notch". Below: "Apps you use can show a timer or a short status here, such as a recording in progress. Off, no app can."
- **Apps:** each app that has shown an activity, with its icon and a switch.
- **Link:** "Add this to your own app" opens the guide page. This is the one developer sentence in the card.

The page is `site/src/guide/` › "Show an activity in the notch", with the protocol table above and the example. It leaves out jargon in the listener's part and keeps the protocol to its own section, as the command line does.

## Performance

- **Hover to expand and play/pause:** unchanged. The activity paths only add a case to the state selectors, and dispatch stays synchronous.
- **The setting off:** nothing, no socket and no key path with a value.
- **On, with nothing live:** one listening socket, no timer.
- **With a clock showing:** one redraw a second from the system. check it by hand while building: CPU and wakeups in Activity Monitor with a clock showing, expecting about one wakeup a second and no more.

## Pull requests

#51 is two pull requests, to be made sub-issues of #49 before the first starts.

1. **The model and the drawing.** `Activities/` in WarbleModel (`Activity`, `ActivityState`, `ActivityPatch`, `ActivityRequest` with its limits, `ActivityHandler`), the actions and effects above, the `ActivityChannel` port with its fake, the `NotchState` and `NotchCard` cases, the views, and a launch argument `-notchPreviewState activity` to see it without a socket, as the other previews do. Linux tests through `reduce` for every row of the actions table, the priority table, the deadline (none with nothing live, the earliest otherwise) and the effects through `EffectRunner`. No socket and no setting, so it can't change anything for a user.
2. **The socket, with Settings and the guide.** `UnixSocket` pulled out of `AgentSocket`, `ActivitySocket` (WarbleCore) and its macOS tests, `PlatformEffects` opening it, the Settings › Activities section and its preference keys, the guide page, the example, `docs/architecture/activities.md` with its row in CLAUDE.md, and the README and landing page lines. Last, a Shot issue to show its recording timer.

One pull request would be about 1,500 lines across three targets and the views. Splitting at the socket keeps the first reviewable on Linux alone and leaves the second with the part that needs a Mac.

## Example and guide

The example is one Swift script, `docs/examples/activity.swift`, that connects, starts a 30-second countdown with a Pause button, prints the events it gets and ends. It runs with `swift docs/examples/activity.swift` and also serves as the recording for the guide. It's outside every Make target and CI, like `docs/demo/`.

A `warble activity` command would be useful for shell scripts, but the command line's names are about to be frozen ([#53](https://github.com/LorcanChinnock/warble/issues/53)), so it can wait for a request.

## Not now

- **Links.** `warble://activity?…`, if a one-shot notice is asked for.
- **Sandboxed senders.** An App Group socket.
- **Per-app approval** in the notch, on first use.
- **An activity over a full-screen app,** as an opt-in like `toastsInFullScreen`.
- **A strip** under the wings that announces a new activity for a moment, as the track toast does.
- **A Swift package** over the socket.
