---
title: Get started
summary: Install Warble, open it for the first time and see what's playing in your notch.
group: Get started
---

Warble is in beta. You can use it every day, but it's still being built, so things change between versions and a few rough edges remain. It needs macOS 15 or later, and runs on Apple silicon and Intel Macs.

## Install Warble

Open Terminal (in Applications › Utilities), paste this line and press Return. It downloads the latest release, checks it against the release's checksum, copies Warble into Applications and opens it:

```sh
curl -fsSL https://warble.lorcanchinnock.com/install.sh | bash
```

macOS doesn't check apps that Terminal downloads, so Warble opens without a warning.

## If you downloaded the zip instead

Download the zip from the [latest release](https://github.com/LorcanChinnock/warble/releases/latest), open it and drag **Warble** into your Applications folder. Apple hasn't notarized Warble, so macOS blocks a browser download the first time you open it. You only do this once.

1. Open Warble from your Applications folder. macOS says it can't check Warble for malicious software. Click **Done**.
2. Open **System Settings**, choose **Privacy & Security**, and scroll down to **Security**.
3. Click **Open Anyway** next to the message about Warble, then confirm with your password or Touch ID.

A small icon of three bars appears in the menu bar, and a window opens to say that Warble is in your notch. It shows the open notch with a made-up song, or the one that's playing, and has one switch, **Open Warble when you log in**. Turn it on to have Warble there after you restart your Mac, then click **Done**. The window opens only this once, and an update never brings it back.

## See what's playing

1. Play something in any app: Music, Spotify, a podcast app, or a video in your browser.
2. The notch slides out a little. The album art sits on its left, and on its right a few bars move while it plays.
3. Hover over the notch. It opens into the player, with the song, how far through it you are, and the controls.

![The open notch, with the album art, the song, how far through it you are and the controls](../../../docs/media/player.png)

Move the pointer away and the notch closes again. [Control playback](/docs/control-playback/) covers everything the player does.

When you pause, the song stays in the notch until something else plays. You can make it leave after 10 seconds or a minute instead, in Settings, and Warble then hides behind the camera. When nothing is playing, Warble shows nothing and does nothing until a song starts. If you point at the notch then, a small card shows the last song that played, with a button to play it again, and goes when you move away. Until a song has played since Warble opened, the card says "Nothing playing" instead.

> [!TIP]
> If you left the switch off and want it later, it's **Open at login** in **Settings…**, from the menu bar icon, under **General**.

## Updates

Warble asks once whether it should check for updates automatically. Whatever you choose, you can check at any time with **Check for Updates…** in the menu bar icon's menu. Warble also goes online to find the album cover for a song playing in your browser, since a browser only gives it a frame of the video. That search sends the song's title and artist to Apple's iTunes Search and nothing else, and no other app's song is looked up. When you click the artist on the open notch, Warble looks up the artist: for Spotify it reads the song's page on Spotify's website, and for a YouTube video it asks YouTube for the video's channel.

> [!NOTE]
> On a display without a notch that has the menu bar, Warble draws a notch of its own at the top of the screen. See [External displays](/docs/external-displays/).
