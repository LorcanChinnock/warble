---
title: Remove Warble
summary: Quit Warble, delete it, and clear away what it keeps on your Mac.
group: Help
---

Warble keeps very little on your Mac: its settings, the last song you played, and a small cache from checking for updates. None of it ever leaves your Mac.

## If you installed it with Homebrew

Paste this into Terminal. It quits Warble and deletes it:

```sh
brew uninstall --cask warble
```

To delete its settings, the last song and its cache as well, use this instead:

```sh
brew uninstall --cask --zap warble
```

## If you downloaded it

1. If you turned on **Open at login**, open **Settings…** from the Warble icon in the menu bar and turn it off.
2. Click the Warble icon in the menu bar and choose **Quit Warble**. If you've hidden the icon, right-click the notch instead.
3. In Finder, open your Applications folder and drag **Warble** to the Bin.

To clear away the rest too:

1. In Finder, press <kbd>⌘⇧G</kbd>, go to `~/Library/Application Support`, and drag the **dev.lorcan.Warble** folder to the Bin.
2. Do the same in `~/Library/Caches`, for its **dev.lorcan.Warble** folder.
3. Then go to `~/Library/Preferences` and drag **dev.lorcan.Warble.plist** to the Bin.

> [!NOTE]
> If you let Warble control Music or Spotify, it may still be listed in System Settings › Privacy & Security › Automation. Once Warble is gone, that entry does nothing.
