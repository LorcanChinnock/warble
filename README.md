<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Warble app icon">
</p>

<h1 align="center">Warble <sup>beta</sup></h1>

<p align="center">
  Your music, in your Mac's notch.<br>
  Free, open source, and private: no account, no cloud, no analytics.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-beta-yellow" alt="Beta">
  <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="GPL-3.0 license"></a>
  <a href="https://github.com/sponsors/LorcanChinnock"><img src="https://img.shields.io/badge/sponsor-%E2%99%A5-ea4aaa" alt="Sponsor Warble"></a>
</p>

<p align="center">
  <a href="https://warble.lorcanchinnock.com">Website</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

<p align="center">
  <img src="docs/media/skip.gif" width="480" alt="The notch opening on hover, then skipping to the next track">
</p>

Warble shows what's playing in the notch at the top of your Mac's screen. Hover over the notch or click it to see the song, then play, pause, skip or switch speakers. When nothing is playing, it stays out of sight, and pointing at the notch says so.

Warble is in beta: it works, and it's still being built.

## Install

```sh
brew install lorcanchinnock/tap/warble
```

Or [download the latest release](https://warble.lorcanchinnock.com/download) and drag Warble into Applications. It needs macOS 15 or later, on Apple silicon or Intel. Warble isn't notarized by Apple yet, so macOS blocks it the first time you open it: the [install steps](https://warble.lorcanchinnock.com/#install) show how to open it anyway. The [user guide](https://warble.lorcanchinnock.com/docs/) covers the rest. Warble follows your Mac's language: English, German, Spanish, French, Italian, Japanese, Korean, Brazilian Portuguese or Simplified Chinese.

## Features

- **What's playing, in the notch.** The album art sits on one side, and on the other a few bars move while it plays. Open it to see the song on a soft glow in the album art's colours, or turn the glow off in Settings for a plain black notch.
- **Controls.** Play, pause, skip, move through the song, and turn shuffle and repeat on or off when the app has them. Drag the volume bar, or scroll over the notch with two fingers: up and down changes the volume, sliding sideways moves through the song and a quick sideways flick skips.
- **Switch speakers.** Move your Mac's sound to its own speakers, headphones or AirPods from the notch.
- **Any player.** Apple Music, Spotify, podcast apps and video in your browser.
- **Calm by default.** A paused song stays for a few seconds, then Warble gets out of the way. When nothing is playing, it hides behind the notch and uses no CPU, and pointing at the notch opens a small note that says nothing is playing.
- **Every Mac.** A main display without a notch, on a Mac without one or an external display, gets a notch Warble draws at the top.
- **For everyone.** Works with VoiceOver, and follows Increase Contrast and Reduce Motion.
- **Little to set up.** Open at login, and a switch for the title in a virtual notch. Right-click the notch, or use the menu bar icon, for Settings, updates and Quit.

## Privacy

Warble collects nothing. It has no account, no cloud and no analytics, and it goes online only to check for updates, after you agree, and to find the album cover for a song playing in your browser, which sends just its title and artist to Apple's iTunes Search. When you click the artist, it asks Spotify or YouTube for the artist's page.

## Contributing

Bug reports, ideas and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to build Warble from source, run the tests and send a change. To report a security problem, see [SECURITY.md](SECURITY.md).

Warble shares its repository layout, tooling and release pipeline with [Shot](https://github.com/LorcanChinnock/shot), a screenshot app by the same author.

## Support

Warble is free, with no ads. [Sponsoring](https://github.com/sponsors/LorcanChinnock) keeps it that way and helps pay to notarize it.

## License

Warble is free software under the [GNU General Public License v3.0](LICENSE).

## Acknowledgements

Warble updates itself with [Sparkle](https://sparkle-project.org), under the MIT license, and reads what's playing with [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter), under the BSD 3-Clause license. See [Acknowledgements](Resources/Acknowledgements.txt).
