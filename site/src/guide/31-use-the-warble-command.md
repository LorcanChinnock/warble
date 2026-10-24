---
title: Use the warble command
summary: Turn on the warble command, then read what's playing and control it from Terminal, scripts, sketchybar or tmux.
group: For developers
---

The `warble` command reads what's playing and does what the buttons in the notch do. Use it in Terminal, in a script, or to feed a status bar such as sketchybar or tmux. It's off at first, so nothing can reach Warble this way until you turn it on.

## Turn it on

1. Right-click the notch, or click the Warble icon in the menu bar, and choose **Settings…**.
2. Choose **Developer**.
3. Turn on **Allow the warble command**.

While it's off, Warble opens nothing for the command, and `warble` tells you how to turn it on. Only programs running as you can reach Warble.

## Get the command

If you installed Warble with Homebrew, `warble` is already there. Skip this part.

Otherwise, in **Settings › Developer**, click **Install** beside **Use warble in Terminal**, and enter your password once. It adds a link to the command inside Warble, so it updates when Warble does. **Uninstall** removes the link.

You can also run it straight from the app:

```sh
/Applications/Warble.app/Contents/MacOS/warble-cli now
```

> [!NOTE]
> Inside the app the command is called `warble-cli`, because a file called `warble` would clash with the app's own `Warble`. A build you made yourself, WarbleDev, uses `warble-dev` for the link, so it never replaces the one for the Warble you installed.

## See what's playing

```sh
warble now
```

```
Playing: Song by Artist
Album: Album
Position: 0:10 of 3:20
App: com.apple.Music
Volume: 40%
```

With nothing playing, it says `Nothing is playing.`

### For a status bar

Add `--json` for one line of JSON:

```sh
warble now --json
```

```json
{"album":"Album","app":"com.apple.Music","artist":"Artist","duration":200,"position":10,"repeat":"all","shuffle":"songs","status":"playing","title":"Song","volume":40}
```

| Key | Meaning |
| --- | --- |
| `status` | `playing`, `paused` or `stopped`. Always there. |
| `title`, `artist`, `album` | What the app says it's playing. |
| `app` | The player's bundle identifier, such as `com.apple.Music`. |
| `position`, `duration` | Whole seconds. A live stream has no `duration`. |
| `shuffle` | `off`, `albums` or `songs`, when the app says. |
| `repeat` | `off`, `one` or `all`, when the app says. |
| `volume` | 0 to 100, when the sound output has a volume. |

A key with nothing to say is left out, so with nothing playing you get only `status` and `volume`. In a script, read it with `jq`:

```sh
warble now --json | jq -r 'select(.status == "playing") | "\(.title) – \(.artist)"'
```

## Control playback

| Command | What it does |
| --- | --- |
| `warble toggle` | Plays when paused, and pauses when playing. |
| `warble play` | Plays. |
| `warble pause` | Pauses. |
| `warble next` | Skips to the next track. |
| `warble previous` | Goes to the previous track. |
| `warble seek 90` | Moves to 90 seconds into the track. `warble seek 1:30` works too. |
| `warble volume 40` | Sets the volume to 40%, from 0 to 100. |
| `warble output AirPods` | Moves the Mac's sound to the output with that name. |

Each command does exactly what its button does, and a command works on whatever Warble is following. `warble output` takes the start of a name or a part of it when only one output matches, such as `AirPods` for `Lorcan's AirPods Pro`. If several match, or none, it says so and lists your outputs, and moves nothing. A name with spaces needs no quotes.

A command that works prints nothing and ends with exit status 0. A mistake prints what's wrong to the error output and ends with a status other than 0, so a script can tell.

| Status | Meaning |
| --- | --- |
| 64 | A command or a value that isn't right, or an output that doesn't match. |
| 69 | Warble isn't running, or the command is off in Settings. Also a sound output with no volume to change. |
| 70, 73, 74 | Something went wrong inside, with the socket or with reading the answer. |

For the same controls from a launcher, see [Control Warble with links](/docs/control-warble-with-links/). Every command and link is in the [reference](/docs/command-and-link-reference/).

## Troubleshooting

- **"Warble isn't answering the command line."** Open Warble, and check that **Allow the warble command** is on in **Settings › Developer**.
- **`command not found`.** Install the command in **Settings › Developer**, or run it by its full path as shown above.
- **It's slow to answer.** The command waits up to 10 seconds. If Warble is waiting on a permission dialog, answer that first.
