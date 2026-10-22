---
title: Control Warble with links
summary: Turn on warble:// links, then play, pause, skip, seek, set the volume and open Settings from Terminal, a launcher or a script.
group: For developers
---

A `warble://` link does what the matching button in the notch does. Use one from a launcher such as Raycast or Alfred, a script, a Shortcuts "Open URLs" action or Terminal's `open`. Links are off at first, so nothing can control Warble until you turn them on.

## Turn on links

1. Right-click the notch, or click the Warble icon in the menu bar, and choose **Settings…**.
2. Choose **Developer**.
3. Turn on **Answer warble:// links**.

While it's off, Warble ignores every link.

## Try one

1. Play something.
2. Open Terminal and run:

```sh
open warble://toggle
```

The song pauses. Run it again and it plays.

> [!NOTE]
> A build you made yourself from the source, WarbleDev, answers `warble-dev://` instead, so it never takes a link meant for the Warble you installed. The routes after it are the same.

## The links

| Link | What it does |
| --- | --- |
| `warble://toggle` | Plays or pauses. |
| `warble://play` | Plays. |
| `warble://pause` | Pauses. |
| `warble://next` | Skips to the next track. |
| `warble://previous` | Goes to the previous track. |
| `warble://seek?seconds=90` | Moves to 90 seconds into the track. |
| `warble://volume?percent=40` | Sets the volume to 40%, from 0 to 100. |
| `warble://expand` | Opens the notch on the display the pointer is on, with the keyboard in it. Run it again to close it. See [Accessibility](/docs/accessibility/). |
| `warble://settings` | Opens Settings. |
| `warble://settings?section=shortcuts` | Opens Settings on a section: `general`, `notch`, `shortcuts`, `developer` or `about`. |

Each link does exactly what its button does. `next` and `previous` skip by track, as the buttons and the keyboard shortcuts do, and `toggle` shows the change at once, before the app catches up.

> [!TIP]
> A link with a route Warble doesn't know, a missing or out-of-range number, or a section that doesn't exist does nothing, and Warble says so. The route names are all lowercase.

## Troubleshooting

- **Nothing happens.** Check that **Answer warble:// links** is on in **Settings › Developer**.
- **Nothing is playing.** Playback links need something playing. Settings and `expand` work either way.
