---
title: Use Warble in Shortcuts
summary: Play, pause, skip, set the volume, switch speakers and read what's playing from the Shortcuts app and Spotlight.
group: For developers
---

Warble adds actions to the Shortcuts app, so a shortcut can control the music and read what's playing. Each does what the matching button in the notch does. They need no setting: they're there once you've opened Warble.

## The actions

Open the Shortcuts app, make a new shortcut, and search for Warble in the action list.

- **Play or Pause**, **Next Track** and **Previous Track** press the same buttons as the notch.
- **Set Volume** sets the Mac's sound output to a number from 0 to 100. If the output has no volume, such as some HDMI displays, the shortcut stops and says so.
- **Switch Sound Output** moves the sound to an output you pick from the list, such as AirPods. If it has gone since you built the shortcut, the shortcut stops and says so.
- **Get Now Playing** gives the status, title, artist, album, app, position, duration and volume, for the next action to use. With nothing playing, the status is `stopped` and the rest are empty.

## From Spotlight

Spotlight lists Play or Pause, Next Track, Previous Track and Get Now Playing. Type the name of the action, such as "Next track", and press Return.

> [!NOTE]
> Warble opens, if it isn't running, when a shortcut asks it to do something.
