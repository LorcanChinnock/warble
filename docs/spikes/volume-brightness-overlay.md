# Spike: replacing the volume and brightness overlay

Findings for [#46](https://github.com/LorcanChinnock/warble/issues/46). Nothing was built. The toast queue it builds on was removed in [#257](https://github.com/LorcanChinnock/warble/issues/257), so this would bring it back from git history. Checked on macOS 27.0.1 (a MacBook with a built-in display), plus what other notch and HUD apps do.

## Answer

Warble can show volume and brightness in the notch, but it can't keep the system overlay from appearing without Accessibility, and brightness needs a private framework. Showing a change next to the system overlay is cheap for volume and not possible for brightness. We recommend not replacing the overlay, and building nothing until someone asks, because a volume notice beside the system overlay would show the change twice.

## Volume

- **Seeing changes.** Already done. `SystemVolume` listens to Core Audio for the volume, mute and default output, and needs no permission. It listens only while the volume shows, so for a notice it would listen while the setting is on and something plays.
- **Showing it.** A notice that comes and goes is a `Notice` in `ToastQueue`, which already keeps its deadline in `AppState.deadline`. A new `Notice.Kind` (say `volumeChanged`) replaces an older one of its kind, so holding the key shows one notice for the last value.
- **The system overlay still appears.** Nothing in the public API stops it, and we found no way to see a change before the overlay is drawn.

## Brightness

- **No public API.** The documented route (`IODisplayGetFloatParameter` with `kIODisplayBrightnessKey`) finds no `IODisplayConnect` service on Apple Silicon, so it reads nothing. An Apple DTS engineer has said there's no supported way to set brightness either ([Apple forums](https://developer.apple.com/forums/thread/666383)).
- **Private framework.** `DisplayServicesGetBrightness` from `DisplayServices.framework` works here (it returned 0.44 for the built-in display) when found with `dlopen` and `dlsym`. It can go in any macOS release, and it rules out the Mac App Store. Warble ships outside the store, so that part doesn't matter, but "no private API" in the issue rules it out.
- **External displays** need DDC/CI through the private `IOAVService`, and it doesn't work over some HDMI ports on Apple Silicon.
- **Seeing changes.** There is no public notification. The alternatives are the brightness keys (below) or polling, and Warble does no polling. Auto-brightness and Control Center's slider would be missed without polling.

## Hiding the system overlay

On macOS 26 and later Control Center draws the volume and brightness popover. Before that it was `OSDUIHelper`, which is still present and not running here. Every app that replaces the overlay does it the same way:

1. Listen for the media keys with a `CGEventTap` on system-defined events.
2. Swallow volume, mute and brightness key events, so macOS never sees them.
3. Change the level itself (Core Audio for volume, `DisplayServices` for brightness) and draw its own overlay.

Examples are [BetterHUD](https://github.com/connorpodea/BetterHUD), [Notchy](https://notchy.dev/mac-volume-hud/), [Eyelid](https://github.com/Nikita19329/Eyelid/pull/8) and [better-osd](https://github.com/0x3654/better-osd). The costs:

- **Permission.** Swallowing a key needs an active tap, which needs Accessibility. BetterHUD says that's all it needs, Notchy says Accessibility and Input Monitoring. We didn't test a tap from Warble's own signature, since this Mac's Terminal already holds both grants, so which of the two a build needs is still open.
- **Fragility.** Unhandled keys must be passed through, or a bug in the tap breaks the keyboard. A tap macOS disables for being slow has to be turned back on.
- **Gaps.** Touch Bar sliders and Control Center sliders send no key, so the system overlay still shows for them. Keyboard backlight keys and external displays need their own handling.
- **Behaviour change.** Once Warble swallows the key it owns the step size, the mute and unmute rules and the haptics, which `SystemVolume.set` doesn't do for key presses today.
- **No sandbox.** Event taps can't run in a sandboxed app. Warble isn't sandboxed, so this is fine.
- **Stopping the helper instead.** Killing or suspending `OSDUIHelper` or Control Center's popover would need no permission, but it's a hack that fights launchd, may need SIP off, and breaks the Mac's own feedback if Warble crashes. We don't recommend it.

## How a build would fit the store

Following CONTRIBUTING.md › Adding a feature:

- **State.** Add `VolumeNotice` (or fold it into `ToastState`) with a setting that starts off. `Notice.Kind` gains `volumeChanged`, and `Notice<Content>` is generic, so the content needs a type that holds a level and a mute flag, or `ToastQueue` becomes a queue of an enum of both kinds of content.
- **Actions.** None new are needed. The listener already ends in `.volumeRead(_:isMuted:)`, which `EffectRunner.readVolume()` dispatches, so `reduce` can post the notice from there. It posts only when the setting is on, something plays and no notch is open, the same rule as the track toast.
- **Effects.** `.followVolume`, the effect that starts and stops the listener, would run "while Expanded shows the card, or the notice is on". The runner starts and stops the listener from that one reason, so with the setting off or nothing playing nothing listens.
- **Ports.** `VolumeControl` already has what's needed, so no new port. A fake exists. Brightness would need a `BrightnessControl` port with a fake, and a real one over `DisplayServices` in WarbleCore. We don't recommend building it.
- **Deadline.** The notice's end is `ToastQueue.deadline`, which is already part of `AppState.deadline`. No timer of its own.
- **Nothing playing.** The notice is posted only while something plays (`shared.showsPlayback`), as the track toast is. With nothing playing there's no listener, no notice and no deadline.
- **Permission.** None for the notice. Replacing the overlay adds Accessibility, to be asked for only when that second setting is turned on.
- **Views.** Each resting notch draws the notice as a toast-like strip, `NotchState.toast` style, with a bar and the level.

## Recommendation

1. Don't replace the system overlay. It needs Accessibility, covers only keys, and a mistake costs the user their volume keys. That cuts against "calm" and "stays out of the way".
2. A volume notice with no permission is possible and fits the store (above), but beside the system overlay it shows the change twice. Its one gain is changes the overlay doesn't show, such as AirPods or a script. That's too little to build now.
3. Skip brightness. It needs a private framework with no change notification.
4. Revisit only if people ask for the overlay to go. That would be a separate setting under a Developer-style card with its own explanation of the permission.
