---
title: Show an activity in the notch
summary: Let an app or a script show a timer or a short status in Warble's notch over a Unix socket, with buttons that send a press back. Covers turning it on, the protocol, the limits and a runnable example.
group: For developers
---

An activity is something short and live that another app shows in the notch, the way Warble shows music: a red dot on the left and `00:42` on the right while a recording runs, with a Stop button when you open the notch. Warble doesn't start any itself. An app or a script asks for one over a Unix socket and keeps it going until it's done.

## Turn it on

It's off at first, so no app can put anything in the notch until you say so.

1. Right-click the notch, or click the Warble icon in the menu bar, and choose **Settings…**.
2. Choose **Activities**.
3. Turn on **Show what other apps are doing in the notch**.

Below the switch, **Apps** lists each app that has shown an activity, with its icon and a switch. An app is on the first time it appears, since turning the feature on was the permission. Turn an app off to end what it's showing and refuse its next one.

With the switch off, Warble opens no socket, and a program that tries to connect finds nothing there.

## What you see

While an activity runs, the notch's wings show the sender's own icon on the left, with the activity's symbol as a small badge on it, and its clock, or a short badge, on the right. It takes the place of the music's art and bars, and music comes back when the activity ends.

Point at the notch to open it. If music plays, the player gets a row below its controls for each activity. With nothing playing, the activity gets a card of its own. Each row has the sender's name, the title, the clock, up to two buttons and a close button, so you can always dismiss an activity.

At most three activities show at once, and two from one app. If there are several, the wing shows the one marked `high` first and then the newest.

## Connect

The socket is `activities.sock` in the folder Warble keeps in Application Support, next to the one the `warble` command uses:

```
~/Library/Application Support/dev.lorcan.Warble/activities.sock
```

A build you made yourself, WarbleDev, uses `dev.lorcan.Warble.dev` in place of `dev.lorcan.Warble`. Only programs running as you can connect. A sandboxed app can't reach the folder, so this is for apps and scripts that aren't sandboxed.

Connecting is the whole check. If nothing answers, Warble isn't running or the setting is off, so show nothing and don't poll.

Keep one connection open for as long as you have an activity. Closing it, or quitting, ends everything it started, so a crashed app never leaves a timer behind. Turning the setting off closes the socket, which looks the same to you.

## The protocol

Each message is one JSON object on its own line, in UTF-8 and ending in a newline, in both directions. A line is at most 4 KB, and every message has `"v": 1`.

```json
{"v":1,"op":"start","id":"recording","title":"Recording Display 1","detail":"Saves to Desktop",
 "icon":{"symbol":"record.circle","tint":"red"},"clock":{"since":1766592000.0},
 "buttons":[{"id":"stop","label":"Stop","symbol":"stop.fill"}],"priority":"normal","lasts":3600}
{"v":1,"op":"update","id":"recording","detail":"Paused","clock":null}
{"v":1,"op":"end","id":"recording"}
```

(The first example is wrapped over two lines here. Send it as one.)

| Field | Meaning | Limit |
| --- | --- | --- |
| `op` | `start`, `update` or `end`. | |
| `id` | Your name for the activity. It's unique within the connection. | 64 bytes |
| `title` | What the card says and VoiceOver reads. | 60 characters |
| `detail` | An optional second line on the card. | 100 characters |
| `badge` | Short text for the right wing when there's no clock. | 8 characters |
| `icon` | `{"symbol": "<SF Symbol name>", "tint": "<colour>"}`, drawn as a badge on your own icon. Tints are `white` (the default), `red`, `orange`, `yellow`, `green` and `blue`. There are no images. | Name: lowercase letters, digits and dots, 64 bytes |
| `clock` | `{"since": t}` counts up from `t`, `{"until": t}` counts down to it, with `t` in seconds since 1970. A clock that reaches zero stays at `0:00` until you end the activity. | One of the two, with a date between 1970 and 2100 |
| `buttons` | Up to two, each `{"id", "label", "symbol"?}`. | Id 32 bytes, label 16 characters |
| `from` | For a script only: the name to show, as "Script: <name>". Required for a script and ignored for a signed app. An `update` can't name it. | 30 characters |
| `priority` | `normal` or `high`. | Two levels |
| `lasts` | Seconds from this message until Warble ends the activity itself. Each `update` that sets it counts again from that message. | 1 to 43200, default 3600 |

An `update` changes only the fields it names, and is checked against the same limits as a `start`. Set `detail`, `badge`, `clock`, `icon` or `buttons` to `null` to clear it, and `lasts` to `null` to go back to the default. `title`, `from` and `priority` can't be cleared. A `start` with an `id` already in use replaces that activity.

A symbol Warble can't draw is left off, and your own icon shows alone. A string over its limit is refused, not cut, so you see the mistake instead of half a sentence in the notch. A clock needs no updates, since Warble draws it from `since` or `until`.

### Replies

Each line you send gets one reply line, in order:

```json
{"v":1,"re":"start","ok":true}
{"v":1,"re":"start","ok":false,"error":"title is 74 characters; the most is 60"}
```

Errors are sentences, and a failure always carries `re`, the operation it answers when Warble could read one. An unknown version gets an error naming the one Warble speaks.

### Events

Warble also sends events, which carry `event` in place of `re`:

```json
{"v":1,"event":"button","id":"recording","button":"stop"}
{"v":1,"event":"ended","id":"recording","reason":"dismissed"}
```

A button press goes back only to the app that made the activity, and nothing else happens: no link opens and no command runs. Answer it with an `update` or an `end`, since Warble doesn't guess what a button does.

The `ended` reasons are `dismissed` (the user closed it), `expired` (`lasts` ran out) and `blocked` (the user turned your app off in Settings). Warble sends nothing when you end an activity yourself, replace it, or close the connection.

### Limits

- Three activities at once across all apps, and two for one connection.
- 20 lines a second for one connection. A line over that gets `"error": "slow down"`.
- A line that has started must finish within a few seconds. A connection that has nothing to say can stay quiet for hours.

## Who the notch says you are

macOS shows no prompt for a Unix socket, so Warble doesn't take your word for who you are. It reads who is on the other end of the connection once, when you connect, and checks that process's code signature.

- **A signed app** is an app in a top-level `.app` bundle that's signed with a team ID. Its name and icon come from the app, and Settings keeps it under its team ID and signing identifier, so another app can't take its place.
- **Anything else is a script**: a shell, `nc -U`, `python3`, `swift`, an unsigned program or an ad hoc build. A script names itself with `from`, and the notch and Settings show it as "Script: <name>", so nothing it does can pass for a signed app. Turning one script off doesn't turn off every script on the same interpreter.

The wing always draws the sender's real icon, or a generic mark for a script. Your `icon` is only a badge on it, so no sender can make wings that look like another app's.

## Try the example

[`docs/examples/activity.swift`](https://github.com/LorcanChinnock/warble/blob/main/docs/examples/activity.swift) connects, starts a 30-second countdown with a Pause button, prints each event and ends. Turn on **Settings › Activities** and run:

```sh
swift docs/examples/activity.swift
```

Press **Pause** in the open notch, and the script prints the button press and answers it with an `update`. It shows up as "Script: Countdown example". Press the close button, or let it count down, and it ends.

You can also talk to the socket by hand:

```sh
printf '%s\n' '{"v":1,"op":"start","id":"hi","from":"Terminal","title":"Hello","lasts":10}' | nc -U ~/Library/Application\ Support/dev.lorcan.Warble/activities.sock
```

The activity ends as soon as `nc` closes the connection, so use the example for anything you want to see for more than a moment.
