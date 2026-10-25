# Activities

Read this before changing what other apps can show in the notch: the activities socket, who a sender is, the Activities card in Settings or the guide page. Back to the [architecture index](../../CLAUDE.md#architecture). The protocol and why it is a socket are in [the design](../spikes/notch-activities.md), and what the notch draws for an activity is in [the notch](notch.md).

Settings › Activities › Show what other apps are doing in the notch (`PreferenceKey.activities`, off at first) lets another app, or a script, show a timer or a short status in the notch. `ActivityState` (WarbleModel, `Activities/`) holds the setting, the senders Settings turned off (`PreferenceKey.activityBlocked`, an array of identifiers), every sender that has shown one (`PreferenceKey.activityApps`, identifier to name, which `.saveActivityApps` writes) and the live activities. `AppEnvironment` reads all three at launch and `NotchController` dispatches `.activitiesChanged` and `.activityBlocklistChanged` when the defaults change.

## The socket

`AppState.listensForActivities` follows the setting, and `settle` asks for `.listenForActivities(true)` or `false` once each time it changes, which `PlatformEffects` carries out through `ActivitySocket` (WarbleCore, `Activities/`). With the setting off no `activities.sock` exists. On, there is one listening socket and no timer, and a connection that says nothing costs nothing.

- **Where.** `activities.sock` is next to `agent.sock` (`RemoteSocketPath.activitiesURL`), in the same 0700 folder, at 0600, and each peer's user is checked. `UnixSocket` holds what it and `AgentSocket` share: `address(of:)`, `listen(at:)` (the folder, a stale socket and the mode), `peerUser`, `setTimeout`, `write` and `keepSignalsOff`. `AgentSocket` keeps thin forwards for the ones its tests call.
- **One connection per sender.** The connection stays open for the sender's activities. Each gets a number from 1, which is `ActivityKey.client`, and a `DispatchSourceRead` on one queue reads it without blocking. `ActivitySocket` is `@MainActor`: each read hops to the main queue in turn, so `ActivityHandler.handle(_:from:)` runs on the main actor in the order the lines arrived and its reply is written straight away. Writes never wait: one that can't finish closes the connection, since its sender isn't reading.
- **Its own line reader.** Each connection has a buffer that keeps the bytes after a newline, so two lines in one read are both answered in order. A line over `ActivityLimits.lineBytes` that did arrive whole gets the handler's error and the connection stays. A half line past that size with no newline, or one that takes over `partialLineTimeout` (five seconds) to finish, gets an error line and the connection closes. There is no idle timeout.
- **A connection closing** calls `handler.closed(client:)`, which dispatches `.activityClientClosed`, so a crashed app never leaves a timer behind. `stop()` closes every connection, which each sender sees the same way, and removes the socket. A write to a connection that has gone is dropped (`ActivityChannel.send`).
- **The sandbox** is a limit: a sandboxed app can't reach the folder, so v1 serves apps and scripts that aren't sandboxed.

## Who a sender is

`ActivityPeer` identifies the process once, at connect, off the main actor: `LOCAL_PEERTOKEN` names that process and not a process ID that could be reused, `proc_pidpath` gives its executable and `SecCodeCopyGuestWithAttributes` its signature, which must be valid both running and on disk (the sealed Info.plist the name comes from). `ActivityPeer.classify` then decides, with no Mac needed to test it:

- A signed app is an executable at `Name.app/Contents/MacOS/…` in a bundle with no other bundle (`.app`, `.framework`, `.xpc` and the like) above it, signed with a team ID, and not one of the interpreter bundle identifiers in `ActivityPeer.interpreters` (`org.python.python` to start). Its identifier is the team ID and signing identifier, its name is the app's display name, and its `bundleIdentifier` is the signing identifier, so the icon and the key come from the signature and never from a plist the app could write.
- Everything else is a script, keyed by its executable's path with `bundleIdentifier` nil. `ActivityHandler` appends the script's `from`, so blocking one script doesn't block every script on the same interpreter. A script's name is its raw `from`, and the views write "Script: <name>", localized. `ActivityOwner.label` is the English form for protocol errors and logs only.

The classification is a label for the person reading, not a security boundary: taking a signed app's identity needs its signing key.

## Settings

`ActivitiesSettings` (`SettingsView.swift`) has the switch, the list of apps and the link to the guide. Each app row is its icon (from `ActivityOwner.bundleIdentifier(ofIdentifier:)`, or a generic mark for a script), its name and a switch that is on unless its identifier is in the blocked array. A switch writes the array, `NotchController` dispatches `.activityBlocklistChanged`, and `reduce` ends that app's activities with `blocked` and refuses its next `start` (the handler checks too). The section isn't a link target, so `RemoteCommand.settingsSections` is unchanged.

## Try it

Turn on Settings › Activities in a dev build, then run `swift docs/examples/activity.swift dev.lorcan.Warble.dev`: a 30-second countdown with a Pause button that prints each event and ends. It's outside every Make target and CI. The guide page is `site/src/guide/34-show-an-activity-in-the-notch.md`.

Closing the script, or Ctrl-C, removes its activity. Without a preview flag, `-notchPreviewState activity` still shows the drawing with no socket.

## Cost

The setting off costs nothing. On with nothing live there is one listening socket and no timer, no draw and no CPU. `ActivityPeer`'s signature check runs once per connection on a global queue, not on the socket's queue or the main actor, and the hover and play/pause paths are unchanged.
