---
title: See what you listened to
summary: Turn on a weekly summary of your listening time, top artists and top songs, kept on your Mac.
group: Playback
---

Warble can count how long you listen, and show the last 7 days: your total time, the artists you played most and your most played songs. It's off at first, and everything it counts stays on your Mac.

## Turn it on

1. Right-click the notch, or click the Warble icon in the menu bar, and choose **Settings…**.
2. Choose **Stats**.
3. Turn on **Count what I listen to**.

From then on, Warble counts the time each song plays. Open **Stats** again any time to see the week. It starts empty, since nothing was counted before you turned it on.

## What's counted

- Time a song is playing. Paused time isn't counted, and neither is the gap between songs.
- Skipping past a song in less than a second doesn't count.
- A song is added to the totals once it pauses, changes or stops, so the one playing now shows up when it ends. Quitting Warble counts the song playing then.
- Songs are told apart by title and artist. A podcast episode with no artist counts toward your total time and your top songs, but not your top artists.

## What's kept, and where

For each stretch of a song playing, Warble keeps the title, the artist, when it began and for how long. It's a plain text file in Warble's folder in `~/Library/Application Support`. Nothing is sent anywhere, and Warble deletes anything older than 30 days.

While **Count what I listen to** is off, Warble counts and saves nothing. Turning it off doesn't delete what's there. To do that, click **Clear…** in **Stats**, which deletes everything at once and can't be undone.

> [!NOTE]
> The summary looks back 7 days. Warble keeps 30 days, so a month of listening doesn't pile up on your Mac.
