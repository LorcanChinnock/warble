# Redesign spec

The source of truth for the redesign (#425) inside the repository. The [redesign canvas](https://claude.ai/artifact/6n4yuqCDS21mH5oritjSJz) shows how each screen looks, and was signed off on 11 November 2026. This page records the rules, the values and the copy those boards use, so the build stays the same if the canvas changes later. When the canvas and this page disagree, this page wins. Change it in a PR, and redraw the board afterwards.

The redesign covers Warble's windows and menus: Settings, the update window, a first-run window, the menu bar menu and the notch's right-click menu, plus the website. The notch itself, its states, hover and controls, is out of scope. Nothing here touches the hover → expand path or play/pause.

The boards are HTML mock-ups drawn in the system font. Read a pixel as a point. Their colours stand in for the system's: in the app, use the semantic `NSColor` and SwiftUI styles named below, not the hex values.

## Rules

1. **Native where it's familiar.** Standard window chrome, toolbar tabs, grouped forms (`Form` with `.formStyle(.grouped)`), system toggles, pop-up menus, segmented controls, buttons and menus. Nothing a Mac user has to learn twice.
2. **The notch preview is the personality.** It's the one expressive thing in the app's windows: a black notch on a pastel strip. Every other surface is plain system material.
3. **The default is the simplest view.** Settings opens on Notch, which shows only what changes the notch. About holds the version, updates and acknowledgements.
4. **Calm stays calm.** Warble opens a window on its own only three times: the first-run window, once; Sparkle's one-time question about checking automatically; and the update window after an automatic check the person agreed to.
5. **Yellow marks what's on or chosen,** set with `.tint` on each control rather than as the app's accent colour: switches that are on, the chosen segment, the default button, a waiting update's dot. Text is never yellow. Toolbar tabs, links and menus keep the person's own accent and highlight.
6. **Every screen works with the accessibility settings.** Increase Contrast, Reduce Transparency, Reduce Motion, VoiceOver and keyboard-only use. The system controls cover most of this; the preview, the update window and the first-run window need checking by hand.

Every PR also follows the checklist in #425: matches its board in light and dark, Increase Contrast, VoiceOver names (Accessibility Inspector), keyboard only, Reduce Motion, `make strings`, and `make lint` and `make test` pass. A change to anything the notch draws also runs `make perf`.

## Values

### Colour

The app uses system colours throughout. The design note's two palettes become one: `Native` stays for the notch, and `Warm` is removed with the Settings controls (#427).

| Role | In the app | Board stand-in (light / dark) |
| --- | --- | --- |
| Accent | Asset catalog colour `Yellow` (`Color.warbleYellow`), set with `.tint` on each control. Not the app's accent colour: the system draws the selected toolbar tab's label in that, about 1.6:1 on the light toolbar | `#F6C744` in both |
| Accent edge | 0.5 pt inner edge at 28% black, light appearance only, on any yellow fill Warble draws itself, so it has a 3:1 boundary against the window. A system switch or segment can't take it. #434 measured the yellow switch at 1.6:1 against its group and the chosen segment at 1.3:1 against its track. In standard contrast that stands: the knob's position shows a switch's state, and the system's own chosen segment, white on grey, is about 1.2:1. With Increase Contrast in the light appearance, a switch that's on is a darker gold, `#BE8E14` (3.3:1), and the Size segments keep the system's high-contrast look, since a gold dark enough for 3:1 turns their label white and too faint. The default buttons keep the yellow, with dark text at about 9:1 | `rgba(0,0,0,0.28)` / none |
| Text on accent | `labelColor` of the light appearance, in both | `#1D1D1F` |
| Window | `windowBackgroundColor` | `#F2F2F2` / `#2A2A2C` |
| Group | The grouped form's own background | `rgba(0,0,0,0.03)` / `rgba(255,255,255,0.045)` |
| Text | `labelColor` | `#1D1D1F` / `#F2F2F4` |
| Descriptions | `secondaryLabelColor` | `#5F5F64` / `#A6A6AB` |
| Up to date | `systemGreen` | `#2FA84F` |
| Couldn't check, no feed | `systemGray` | `#8E8E93` |

The preview's strip is the one fixed colour: a 110° gradient from `#FFE6A1` through `#F9C9DE` at 52% to `#CDE5F6`, with a 0.5 pt edge at 12% black. It's the same in light and dark, as the notch is.

#427 found that an app-wide `AccentColor` also colours the selected toolbar tab's label, which breaks rule 5, and that the person's own accent (System Settings › Appearance) wins over it anyway unless they use Multicolour. So the yellow is set with `.tint` on each control, which holds whatever accent the person chose.

### Type

System fonts at fixed sizes.

| Use | Size | Weight |
| --- | --- | --- |
| Rows, buttons, pop-up menus | 13 | Regular |
| Group headings, window title | 13 | Semibold |
| Descriptions under rows, captions, the status line's variants | 11 | Regular, secondary |
| About's status line | 12 | Regular |
| About's name | 20 | Bold |
| Update window's title (offer) | 15 | Bold |
| Update window's title (other states) | 14 | Bold |
| First-run title | 22 | Bold |
| Download sizes and times | 11 | Regular, tabular figures |

### Sizes

| Window | Width | Notes |
| --- | --- | --- |
| Settings | 600 | Height fits the tab, and the window animates between tabs as standard preferences windows do. Content inset 24 × 20 |
| Update window | 540 for the offer, about 500 for the other states | Release notes in a 230 pt scrolling box |
| First run | 500 | Content inset 28 |

| Part | Value |
| --- | --- |
| Settings preview strip | 150 tall, radius 10. The preview inside is drawn scaled down, about 0.63×, so the open card at Large, 221 pt at full size, fits the strip with 10 pt below it; the resting notch scales with it. #428 raised it from the board's 118, where the resting notch was about 12 pt tall |
| First-run preview strip | 150 tall, radius 10, showing the open card, scaled down to fit as in Settings |
| Icons in About and the update window | 64 in About, 56 in the offer, 44 in the other states |

## Settings

#427 builds the window and the tabs, #428 the Notch tab and #429 General and About. The window is a standard preferences window: a unified title bar showing the tab's name, and Notch, General and About as toolbar tabs with an icon over a label. The selected tab has the system's selected-item background. The arrow keys and ⌘1–⌘3 should switch tabs if the chosen implementation gives them for free.

The window opens from the menu bar menu, the notch's right-click menu and a relaunch from Finder, and takes a Dock icon while open, as now. #427 starts with a spike to choose between SwiftUI's `Settings` scene and an own `NSWindow` with `NSTabViewController`.

General holds one setting. The board's note suggests folding it into Notch if it stays that thin. The boards were signed off with three tabs, so build three. #429 can raise it again.

### Notch tab

The preview, behaving exactly as it does now (`NotchPreview`, see [Settings](../architecture/settings.md)), on the 150 pt strip. The open card is 156, 184 or 221 pt tall at full size, so the whole preview is drawn at the scale that fits the Large card into the strip, and a Size change still shows as a change in size. Under it, in 11 pt secondary text: "Point at the preview to open it. Its buttons don't control your music."

| Group | Row | Description | Control | Default |
| --- | --- | --- | --- | --- |
| When a song is paused | Stay visible after pausing | How long a paused song stays before the notch goes quiet. | Pop-up: 10 seconds, 1 minute, Always | Always |
| Opened notch | Size | none | Segmented: Small, Default, Large | Default |
| Opened notch | Song title font | none | Pop-up: Default, Rounded, Mono | Default |
| Opened notch | Heart for Music's Favourites | While Music plays, a heart beside the title adds the song to your Favourites. | Switch | Off |
| Displays without a notch | Show a notch | On an external display, or with the lid closed, Warble draws one. | Pop-up: Only when playing, Always, Off | Only when playing |
| Displays without a notch | Song title in the notch | The middle of the notch shows the title and artist. | Switch | On |

Under the last group: "Your MacBook's own notch never changes."

The settings and their `UserDefaults` keys don't change, only their labels and places. The new group answers the first open question in #425.

### General tab

| Group | Row | Description | Control |
| --- | --- | --- | --- |
| Startup | Open at login | Warble opens each time you log in, so it's there after a restart. It's the same switch as System Settings › General › Login Items & Extensions. | Switch, from `LoginItem` |
| Help | User guide | none | Link row showing `warble.lorcanchinnock.com` and an arrow, opening `/docs/` |
| Help | If nothing shows in the notch | none | Link row, opening `/docs/when-nothing-shows/` |

### About tab

A header: the icon, "Warble" at 20 bold, "Version" and the version, and the status line under it, with Check for Updates… on the right.

| Status | Line | Button |
| --- | --- | --- |
| Up to date | Green dot, "Up to date · checked today at 09:12" (relative day, local time) | Check for Updates… |
| Checking | Spinner, "Checking for updates…" | Cancel, while a check you asked for runs; none during a scheduled check |
| An update is ready | Accent dot with its edge, "Version 0.2.0 is ready" | Update… (default button), opens the update window |
| Couldn't check | Grey dot, "Couldn't reach the update server. Check your connection." | Try Again |
| Couldn't install | Grey dot, "The update downloaded but couldn't be installed." (added by #436, since a failure after the download isn't the connection) | Try Again |
| Dev build, no feed | Grey dot, "This build doesn't update itself." | none |

#429 added two lines the boards don't show. "Up to date" needs a check in this session that found nothing, since Sparkle keeps no result between launches, so a check from an earlier session shows a grey dot and "Last checked today at 09:12" (or yesterday, or the date), with Check for Updates…. A build that has never checked shows no line, just the button. Only the user driver can cancel a check, so #430's own driver gives About its Cancel, for a check you asked for. A scheduled check has nothing to cancel, so it shows no button.

Then the groups:

| Group | Row | Detail |
| --- | --- | --- |
| Updates | Check for updates automatically | "Warble checks once a day for a new version." Switch, Sparkle's own setting |
| Updates | Install updates automatically | "New versions download by themselves and install the next time Warble quits. While it's off, Warble asks before it downloads anything." Switch, Sparkle's automatic downloads, off at first and dimmed while checking automatically is off |
| Updates | What's new | "Release notes ↗", opens `/changelog/` |
| Warble (left column) | User guide, Source code, Sponsor Warble | Link rows with ↗ |
| Acknowledgements (right column) | mediaremote-adapter, Sparkle | Link rows showing "BSD 3-Clause" and "MIT" |

Under them, centred, in 11 pt secondary text: "Made by Lorcan Chinnock. Free and open source."

## Update window

#430 builds it: Warble's own Sparkle user driver, ported from Shot's `UpdateUserDriver` (LorcanChinnock/shot#1228) and drawn with system controls. The window is titled "Software Update", with the close button only. The update's status, the offer and the release-notes parsing live in WarbleModel, with tests. Sparkle's standard alerts still handle the first question about checking automatically, "You're up to date" and errors.

| State | When | Title | Text | Buttons |
| --- | --- | --- | --- | --- |
| Offer | A check finds an update | Warble 0.2.0 is ready | You have 0.1.0-beta.14. The download is 6 MB, and Warble quits and reopens to finish, which takes a few seconds. | Skip This Version (left), Remind Me Tomorrow, Install and Relaunch (default) |
| Checking | Only after Check for Updates…; a scheduled check never shows it | Checking for updates… | none | Cancel |
| Downloading | After Install and Relaunch | Downloading Warble 0.2.0 | A progress bar, then "3.2 of 6.0 MB" and "About 5 seconds left" | Cancel |
| Ready to relaunch | The download finishes | Warble 0.2.0 is downloaded | Warble quits and reopens to finish. Your music keeps playing. | Later, Relaunch Now (default) |
| Installed while running | Another installer replaced Warble while it ran | Warble 0.2.0 is installed | It was installed while this copy was running. Relaunch to start using it. | Later, Relaunch (default) |

- The offer shows the release notes for every version since the installed one, in a scrolling box, and under it a checkbox, "Install updates automatically from now on". It turns on the same setting as About's Install updates automatically, which is where it's turned off again.
- Closing the window while it downloads keeps the download going, and the menu shows its progress.
- Later on Ready installs the update the next time Warble quits.
- Installed while running replaces the `NSAlert` that was in `Updater.offerRelaunch(installed:)`.
- Install and Relaunch downloads, then shows Ready, rather than relaunching as soon as the download is ready as Shot's window does.
- The release notes are the last 10 GitHub releases' bodies, which the release workflow embeds in the feed, cut at the installed version. Features show as New, Bug Fixes as Fixed and Performance Improvements as Faster. #430 added this, since the feed carried only the newest release's notes.
- Remind Me Tomorrow waits for the next daily check, so it's hidden while Check for updates automatically is off, and a critical update has neither it nor Skip This Version, as in Sparkle. Closing the offer is Remind Me Tomorrow, closing Checking is Cancel, and closing Installed while running is Later.
- The window takes a Dock icon while it's open, as Settings does, so it can come to the front from the menu bar.
- A menu bar app's window can open behind others, so the menu still offers a waiting update (see Menus).

## Menus

#431 builds both menus. Only the menus change; the notch doesn't.

**Menu bar menu,** in this order: About Warble, Check for Updates…, a separator, Settings… ⌘,, a separator, Quit Warble ⌘Q. About Warble opens Settings on the About tab.

**While an update waits,** the menu bar icon keeps its bars and gains a 6 pt dot at its top right, with a 1.5 pt ring in the menu bar's colour, in place of today's `arrow.down.circle`. "Update to 0.2.0…" with an accent dot replaces Check for Updates… and opens the update window. The icon's VoiceOver name becomes "Warble, update available".

**Right-click on the notch:** Open <app> and Copy Song and Artist while a song with a title shows, a separator, then the menu bar menu's items in the same order.

**While an update downloads,** the update item shows its progress, "Downloading 0.2.0 (53%)…", whether or not the update window is open, and opens the window. The window's other states leave the item as Check for Updates… or the waiting update.

- `AppMenu` and `UpdateMenuItem` (WarbleModel, tested) give both menus their items, order and update item, so the two can't drift apart.
- The menu bar icon's dot is part of the template image, so it takes the menu bar's own colour like the bars, as the board draws it, and the ring is cut out of the image rather than drawn. It sits up and to the right of the short bar: straight above it, the two read as an "i".
- The menu item's dot is the icon's yellow, 7 pt, with the accent edge in the light appearance only, drawn after the title as an image.

## First run

#432 built it: one of the three windows Warble opens on its own (rule 4), shown once, at first launch. It never opens for someone updating from an earlier version. #432 tells them apart by the keys in Warble's own stored settings, read before Sparkle starts: every release has had Sparkle, which stores `SUHasLaunchedBefore` on its first start, so even someone who never opened Settings has it. Any of those keys, or the window's own `firstRunShown`, keeps the window shut (`FirstRun`, WarbleModel, tested).

- No title in the title bar, the close button only. VoiceOver and Mission Control name it Welcome to Warble. Escape closes it too.
- The preview strip, showing the open card with the song that's playing, or `NotchDemo`'s made-up song. It holds the card open (`NotchPreview`'s `holdsOpen`), so it isn't a control there and takes no keyboard focus.
- Title: "Warble is in your notch".
- Text: "Play something in any app, then point at the notch to see the song and control it. When nothing's playing, Warble stays out of sight." On a Mac without a notch, the text says Warble draws one at the top of the screen.
- One row: "Open Warble when you log in", described "So it's still there after you restart your Mac.", a switch, off.
- Footer: "Settings are in the menu bar, under Warble's icon." and Done, the default button.

It doesn't ask for the Automation permission that ScriptSource needs. That stays with the system's prompt when it's first needed, which answers the second open question in #425.

## Website

#433 refreshes the site. It keeps the Warm look ([Website](../architecture/website.md)), with no new tokens. The Settings guide page is rewritten for the tabs, with the new screenshots on a pastel figure panel, and a new Updates page sits beside it under Reference. The panel's gradient mixes the site's own yellow, pink and sky, so it adds no tokens. Screenshots of the app's windows are taken from WarbleDev at 2×, in light only, since the panel looks the same in dark mode as the app's preview strip does.

## Coverage: boards

Each board, the issue that builds it, and where it lands. #436 ticks **QA** after walking the board in the running app in light and dark.

| Board | Issue | Files | QA |
| --- | --- | --- | --- |
| Settings › Notch (light) | #427 window and tabs | `Settings/SettingsWindow.swift`, `Settings/SettingsView.swift`, `Design/Warm.swift` and `Design/SettingsControls.swift` removed, the three architecture notes | ☐ |
| Settings › Notch (light) | #428 | `Settings/SettingsView.swift`, `Settings/NotchPreview.swift` (strip height and the preview's scale), `NotchLayout.previewScale` in WarbleModel with its tests, `docs/architecture/settings.md`, the guide's label renames | ☐ |
| Settings › Notch (dark) | #428, checked by #434 | as above | ☐ |
| Settings › General | #429 | `Settings/SettingsView.swift` | ☐ |
| Settings › About, with update status variants | #429 | `Settings/SettingsView.swift`, `App/Updater.swift`, `WarbleModel/Updates/UpdateStatus.swift`, `WarbleCore/App/UpdateStatusLabel.swift` | ☐ |
| Update window › offer | #430 | `App/Updater.swift`, `App/DockIcon.swift`, `Update/UpdateUserDriver.swift` and `Update/UpdateWindow.swift`, `Design/YellowDefaultButton.swift`, `WarbleModel/Updates/UpdateOffer.swift` and `ReleaseNotes.swift` with their tests, `WarbleCore/App/UpdateWindowLabel.swift`, the release notes in `.github/workflows/release.yml` | ☐ |
| Update window › other states | #430 | as above, and About's Cancel in `Settings/SettingsView.swift` | ☐ |
| Menu bar and right-click menus | #431 | `App/WarbleApp.swift`, `App/StatusItem.swift` (#434 replaced `MenuBarExtra`), `Notch/NotchMenu.swift`, `Design/MenuImages.swift`, `App/Updater.swift` (`menuItem`), `WarbleModel/Menu/AppMenu.swift` with its tests, `WarbleCore/App/AppMenuLabel.swift` | ☐ |
| First-run window | #432 | `App/FirstRunWindow.swift`, `App/AppDelegate.swift`, `App/AppEnvironment.swift`, `App/DockIcon.swift`, `Settings/NotchPreview.swift` (`holdsOpen`), `WarbleModel/FirstRun/FirstRun.swift` with its tests | ☐ |
| Website › guide › Settings | #433 | `site/src/guide/80-settings.md`, `site/src/guide/85-updates.md` and its card `site/public/og/updates.png`, the figure panel in `site/src/lib/guide.ts` and `site/src/styles/global.css`, `docs/media/settings-notch.png`, `settings-about.png`, `update-offer.png` and `menu-update.png` in place of `settings.png` and `settings-more.png`, links to Updates in `01-get-started.md` and `10-control-playback.md`, `docs/architecture/website.md` | ☐ |

The file lists are where the work is expected to land. Each PR corrects its row.

### Whole-app checks

These run once across every board after #427–#432, and tick nothing above. #434 ran them on 12 November 2026 and fixed what failed in #450 and #451.

| Check | Issue | Done | What #434 found |
| --- | --- | --- | --- |
| Dark mode, Increase Contrast and Reduce Transparency | #434 | ☑ | Dark and Reduce Transparency needed nothing. With Increase Contrast, a switch that's on became a darker gold and the Size segments the system's own (see Accent edge) |
| VoiceOver and keyboard only | #434 | ☑ | Settings no longer opens with focus on the preview. The menu bar menu moved to AppKit, so the update item's name no longer ends in U+FFFC. Escape closes the first-run window and every update state. Names were checked in the accessibility tree, not by listening |
| A long pseudo-language | #434 | ☑ | With `-NSDoubleLocalizedStrings YES`, the offer's buttons now stack and About's link values wrap |
| `make perf` against `main` | #434 | ☑ | No change beyond noise |

## Coverage: guide pages

Every page in `site/src/guide/` the redesign changes. #435 updates the text and ticks **Updated**.

#435 checked every page against the app on 12 November 2026. #449 had already done most of it, and the screenshots it took still match after #450 and #451. #435 fixed what was left: Song title in the notch is on at first, not off; When nothing shows names the About tab; Remove Warble says Open at login is on the General tab; Settings says ⌘, also works from the app menu while a window is open; and Accessibility says "a notch Warble draws" rather than "a virtual notch".

| Page | What changes | Build issues | Updated |
| --- | --- | --- | --- |
| 01 Get started | The first-run window and Open at login from it | #432 | ☑ |
| 80 Settings | Rewritten for the tabs, the new names and groups; new screenshots | #428, #429 | ☑ |
| New: Updates | The update window, About's status, the menu's dot | #430, #431 | ☑ |
| 10 Control playback | The heart setting's name; the right-click menu's items and order | #428, #431 | ☑ |
| 20 External displays | The Show a notch and Song title in the notch setting names | #428 | ☑ |
| 90 Nothing shows | The first-run window and the About tab | #432, #429 | ☑ |
| 95 Remove Warble | Setting names | #429 | ☑ |
| Landing page and README | Settings and update mentions: the README's Little to set up and a new Updates itself point, and the landing page's Free card. Neither shows a Settings or update screenshot | #433 | ☑ |
