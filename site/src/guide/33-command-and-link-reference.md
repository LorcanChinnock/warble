---
title: Command and link reference
summary: Every warble command and warble:// link in one place, with the exit statuses and the JSON keys. Their names are stable.
group: For developers
---

Every command and link here does what the matching button in the notch does. The names are settled: before 1.0 they change only on purpose, and a change is in the changelog.

For setup and examples, see [Use the warble command](/docs/use-the-warble-command/), [Control Warble with links](/docs/control-warble-with-links/) and [Use Warble in Shortcuts](/docs/use-warble-in-shortcuts/).

## Commands and links

| Does | Command | Link | Shortcuts action |
| --- | --- | --- | --- |
| Reads what's playing | `warble now [--json]` | none | Get Now Playing |
| Plays or pauses | `warble toggle` | `warble://toggle` | Play or Pause |
| Plays | `warble play` | `warble://play` | none |
| Pauses | `warble pause` | `warble://pause` | none |
| Next track | `warble next` | `warble://next` | Next Track |
| Previous track | `warble previous` | `warble://previous` | Previous Track |
| Seeks, in seconds from the start | `warble seek <seconds>` | `warble://seek?seconds=<seconds>` | none |
| Sets the volume, 0 to 100 | `warble volume <0-100>` | `warble://volume?percent=<0-100>` | Set Volume |
| Moves the sound to an output | `warble output <name>` | none | Switch Sound Output |
| Opens the notch with the keyboard in it | none | `warble://expand` | none |
| Opens Settings | none | `warble://settings` | none |
| Opens Settings on a section | none | `warble://settings?section=<section>` | none |

- `<seconds>` on the command line is seconds, such as `90`, or `1:30`. In a link it's a number of seconds.
- `<section>` is `general`, `notch`, `shortcuts`, `developer` or `about`.
- The command line and links are each off until you turn them on in **Settings › Developer**. Shortcuts actions always work.
- A build you made yourself, WarbleDev, answers `warble-dev://` instead of `warble://`.

## Exit statuses

| Status | Meaning |
| --- | --- |
| 0 | The command worked. |
| 64 | A command or a value that isn't right, or an output that doesn't match. |
| 69 | Warble isn't running, or the command is off in Settings. Also a sound output with no volume to change. |
| 70, 73, 74 | Something went wrong inside, with the socket or with reading the answer. |

## `warble now --json`

`status` is `playing`, `paused` or `stopped`. `title`, `artist`, `album`, `app` (the player's bundle identifier), `position` and `duration` (whole seconds), `shuffle` (`off`, `albums` or `songs`), `repeat` (`off`, `one` or `all`) and `volume` (0 to 100) are left out when there's nothing to say.
