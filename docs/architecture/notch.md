# The notch

Read this before changing the panel, its states, hover, displays, scrolling or the keys it takes. Back to the [architecture index](../../CLAUDE.md#architecture).

## Surfaces and displays

`NotchController` (`Sources/Warble/Notch`) keeps a `NotchSurface` for each camera housing that `VirtualNotch.housings` (WarbleModel) returns: the built-in display's notch, and a virtual one at the top centre of the main display while no display has a real notch (the lid is closed, or the Mac has none). Each surface puts its `NotchPanel` over its housing in a `NotchState`, at the frame `NotchLayout` works out, while `PlayerModel` holds what's playing once for all of them. The controller only turns displays, from the `DisplayProvider` port (`Displays`), into surfaces and dispatches `.housingsChanged`, again whenever they change. In `Store.onChange` it copies the state into `PlayerModel` and has each surface draw what `AppState` says for it (`NotchSurface.apply(_:)`, then `update`). Turning mirroring on or off sends several screen changes while the window server rebuilds the displays, and it moves windows to fit each half-built arrangement. `NotchSurface.draw` skips a layout whose frame hasn't changed, so `NotchSurface.replace()` puts the panel back where its layout has it, on each layout and whenever `NotchPanel` reports a move (`onDisplaced`).

## When a virtual notch is there

`VirtualNotchVisibility` (WarbleModel) is Settings' choice for a notch Warble draws: only while playing, always, or off. `Notches.notchState` applies it to a virtual surface alone, so a real notch is never affected by it. Off is Hidden at all times. Only while playing is Hidden at Idle. Always is Empty at Idle. A full-screen app still hides every notch.

## The nothing-playing note

At Idle a real notch, and a virtual one that Settings keeps always, is `NotchState.empty`: the housing's own shape over the display, with nothing in it (`NotchLayout.frame(.empty)` is the housing, so the wings slide in and the content fades out to it, and the panel stays). It takes the hover over the housing, and `HoverIntent` opens it after `expandDelay`, as for the player, into `NotchState.note` (`NotchState.isOpen` is true for it and for Expanded). The note is a short card under the housing (`NotchLayout.noteDrop`) that says "Nothing playing" (`NoteContent`, in `NotchView`), with no controls. It closes when the pointer leaves or on a click elsewhere or Escape, since `Notches.follow` watches clicks and takes Escape for any open notch, but it follows no volume, since it has no slider. A song that starts while it is open turns it into the player, because `notchState` goes by whether something plays. Nothing is scheduled until the pointer is on an empty notch, and nothing after it leaves. Scrolling over an empty notch does nothing, since `reduce` ignores `.scrolled` while nothing plays. A virtual notch that isn't kept is Hidden, so it has nothing to point at, and a full-screen app hides all of them.

## Full-screen apps

The panel joins every Space, full-screen ones too, since a nonactivating panel at its level joins them whatever its collection behaviour asks. A full-screen app hides the notch on its display instead: `FullScreenSpaces` (`Sources/Warble/Displays`) reads each display's current Space type from the window server (`CGSCopyManagedDisplaySpaces`, looked up with `dlsym`, so without it no display counts as full screen), and `NotchController` dispatches `.fullScreenChanged` on `NSWorkspace.activeSpaceDidChangeNotification` and each layout, never on a timer. `AppState.Surface.isFullScreen` makes `notchState` Hidden, so the notch draws nothing and takes no hover, and the panel lets clicks through (`ignoresMouseEvents`).

## Geometry

macOS reports the housing to the half point, so its edges and height can fall on half points. AppKit snaps windows to whole points, so the panel's window grows out to whole points on both sides (`NotchLayout.window(for:)`) and draws its shape centred, at the housing's exact width and height. The resting corners and wings follow the housing's height (`NotchLayout.cornerRadius`, `wing`), so they stay the same physical size at every display scale; `Tests/WarbleModelTests/Notch/MeasuredHousings.swift` holds what a 15-inch MacBook Air reports at each scale.

## The title in a virtual notch

With the setting on, a virtual notch draws the title between the art and the bars (`VirtualTitle`, in `RestingContent`). `TrackTitle` (WarbleModel) cuts tags such as "- Remastered 2009" from the title and picks what fits the housing's width from widths the view measures: title and artist, the title alone, or the title with its end faded. A title that doesn't fit scrolls while the song plays: `TitleScroll` (WarbleModel) decides when (cut, playing, Reduce Motion off) and gives the speed (18 points a second) and the loop, and `ScrollingTitle` runs it as one repeating Core Animation translation with both edges faded, at 15 to 20 frames a second, so the app does no work per frame and sets no timer. The animation lives in the view, so it ends when the song pauses, Reduce Motion turns on or the notch leaves Resting. Paused, or with Reduce Motion, the title is still with its end faded, as before, and a paused track's title turns grey until Idle hides the notch. `NotchRender.showsTitle` carries `AppState.titleInNotch` to the panel.

## Hover and dismissal

`HoverIntent` (WarbleModel) decides when the pointer opens a notch into Expanded, after `expandDelay` or at once on a click, and closes it again: it takes timestamped events and returns the next deadline instead of running timers. Each notch's lives in `AppState.surfaces`, which is `Notches` (WarbleModel, `Notch/`), a `Feature` like the rest: it handles the actions about the notches themselves, reads the other features' parts through `SharedState`, and works out `notchState` and `answersPointer` from them, so its deadline joins the store's one timer. It also settles itself (`Notches.settle` starts a hover over when a notch stops answering) and asks for the click, Escape and volume effects once each when their reason changes (`Notches.follow`); the settle pass in `reduce` keeps only what couples features, such as the pointer holding off Idle. A surface dispatches `.pointer` from a tracking area over only the camera housing while resting and the whole panel once open, and `.hover(_, .click)` for a click on the panel, which also closes any other open notch. Only while a notch is open does `reduce` ask for `.watchClicksOutside` (a global click monitor in `PlatformEffects`) and, with the pointer on it, `.takeEscape` (a temporary `HotkeyCenter` key through the `HotkeyRegistrar` port, so no permission is needed); both dispatch `.dismiss`.

## Morphing between states

Between states the shape morphs on one spring while the content cross-fades; with Reduce Motion the shape changes at once and only the content fades. The panel grows before a morph and shrinks after it, so nothing is clipped.

## Expanded: controls and volume

Expanded holds the playback controls. They dispatch `.command`, and `reduce` shows play/pause, a seek and the shuffle and repeat modes at once (`PlaybackState.playing(_:at:)`, `seeked(to:at:)`) and asks for `.send`; the app's next report replaces that guess. Warble has no speed control: the adapter can't set a chosen speed (its `speed` only steps the app's own list), and #143 was dropped. `SystemVolume` (WarbleCore) reads and sets the default output's volume through Core Audio. `reduce` asks for `.followVolume`, which listens for its changes, only while a notch is open, and scrolling over the panel in any state goes through `ScrollGesture` (WarbleModel), which keeps the direction a trackpad gesture starts in and ignores the coasting after fingers lift. Up and down dispatches `.scrolled` with the volume read just before (or, within half a second of the last scroll, the volume it set, which `HeldVolume` keeps, since a device can report an old one), as `VolumeScroll` works out. A slow slide sideways dispatches `.scrubbed`, at most every 0.1 s, which `reduce` turns into a seek shown at once. A flick (over 1400 points a second and 60 points) sends next or previous, to the right for next. A mouse wheel only sets the volume. None of it does anything while nothing plays.

## Previews

To see the notch without playing anything, launch with `open build/WarbleDev.app --args -notchPreviewState resting`, which shows a preview track instead of reading the adapter, and hover or click it. Add `-notchPreviewVirtual YES` to draw the virtual notch instead, on a Mac that has a notch.

## The context menu

A right-click or Control-click on a notch that's showing opens `NotchMenu`: the app it follows, Settings, updates and Quit, so Warble can be reached from the notch as well as the menu bar. `NotchPanel.sendEvent` takes the click before SwiftUI, and while the menu is open `HoverIntent` keeps a resting notch resting and `reduce` lets go of Escape, so the key closes the menu.

## Keys

`HotkeyCenter` (`Sources/Warble/Keys`) holds the one key Warble takes from every app, only briefly and through the `HotkeyRegistrar` port, so no permission is needed: Escape while a notch is open with the pointer on it (`.takeEscape`). Warble has no other global shortcut, and no key reaches a notch directly, since `NotchPanel` never becomes key.
