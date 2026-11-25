---
title: When nothing shows
summary: Find out why the notch shows nothing while something plays, and fix it.
group: Help
---

Warble normally shows whatever plays in any app, your browser included. When the notch stays hidden while something plays, work down this list.

## Check the basics

- **Is something playing?** A paused song stays in the notch until something else plays, unless you chose 10 seconds or 1 minute in Settings, and with nothing playing the notch is empty. If the paused song has left, point at the notch to see it again, with a play button. If no app has a song loaded, you see a small "Nothing playing" note instead.
- **Is an app full screen?** The notch on that display hides until you leave full screen.
- **Is Warble running?** Look for its three-bar icon in the menu bar. If it isn't there, open Warble from your Applications folder. If it's gone after every restart, turn on **Open at login** in **Settings…**, under **General**. It's the same switch the window that opened the first time offered.

## Reading what's playing

Warble reads what's playing directly from macOS. When it can't, it falls back to following only Music and Spotify, so other apps, such as your browser, don't show.

- **Part of Warble is missing.** Run the [install command](/docs/get-started/) again.
- **macOS won't let Warble read what's playing.** This can happen after a macOS update. Click the menu bar icon and choose **Check for Updates…** to get the version of Warble that works with it. The **About** tab of **Settings…** shows the version you have and whether a newer one is ready.
- **This kept stopping.** Quit Warble and open it again. If it keeps happening, check for updates.

## Permission for Music and Spotify

While Warble follows Music and Spotify itself, it needs your permission to control them. macOS asks the first time each one plays. If you clicked **Don't Allow**:

1. Open **System Settings**, choose **Privacy & Security**, then **Automation**.
2. Under **Warble**, turn on **Music** or **Spotify**.
3. Play something again.

> [!NOTE]
> Warble also asks for this permission when it can't read what's playing directly, the first time you open the notch on a Music song (to show its heart), and the first time you click the artist of a Spotify song.
