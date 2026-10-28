# Spike: playback on other devices

Findings for [#295](https://github.com/LorcanChinnock/warble/issues/295). Not started on hardware: the Mac-to-Mac design below is desk research, and everything about an iPhone waits for the test plan to be run. Nothing here has been checked on a device yet, and the statements about Apple's frameworks come from their documentation, not from a test.

## Tooling

The iPhone tests reuse `docs/spikes/likes/likes.sh` (see [the likes spike](likes.md#tooling)): `rec` records the stream, `cmds` lists the commands the now playing app supports, and `send` sends any MediaRemote command ID. Set `ARTWORK=1` on `rec` to keep the artwork, which question 1 needs.

## What to expect

- **iPhone playing to the Mac over AirPlay.** If the Mac is the AirPlay receiver, the audio is played by the Mac's own media session, so the stream may report it like any other source. The open points are the bundle identifier it reports, whether the artwork and position arrive, and whether `send` reaches the iPhone or only the Mac's session.
- **Handoff.** A track handed to the Mac is played by an app on the Mac, which Warble already reads. There is no remote session involved, so this case probably needs nothing and should be confirmed.
- **An iPhone that isn't connected.** Apple has no public API for reading another device's session, and the adapter only sees what MediaRemote reports on this Mac. The test is whether anything about the iPhone appears at all.

## Two Macs

Showing the other Mac's track means every Mac runs a small service. The cheapest options, from the documentation:

| Route | What it needs | Cost |
| --- | --- | --- |
| Bonjour on the local network | A listener and a browser on each Mac, `NSBonjourServices` in `Info.plist`, and the Local Network permission prompt | Network activity and a permission prompt on every Mac, running whenever the setting is on |
| iCloud (key-value store or CloudKit) | An iCloud entitlement, which needs a provisioning profile for a Developer ID signature | Warble has no Developer ID certificate yet ([#304](https://github.com/LorcanChinnock/warble/issues/304)), and the track would round-trip through Apple's servers |
| Handoff (`NSUserActivity`) | Continuity between a user's own devices | Built to continue an activity, not to show or control a session |

Whichever route is chosen, the Mac that sends commands would also need to receive them on the playing Mac, so each Mac needs the listener, not only the one being watched. That runs against CLAUDE.md's rule that when nothing is playing Warble "draws nothing and uses no CPU: no timers, no polling", so it would have to start off, and it should open its connection only while the setting is on.

## Test plan

Run these with the dev build of the adapter from `likes.sh`, and quit Warble first so it doesn't hold the adapter. Each case gets its own NAME: `airplay`, `handoff` or `unconnected`.

1. **AirPlay.** On the iPhone, play a song in Music or Spotify and AirPlay it to this Mac. Run `ARTWORK=1 docs/spikes/likes/likes.sh rec airplay`, then after 10 seconds `docs/spikes/likes/likes.sh cmds airplay`. In `out/airplay.jsonl`, note `bundleIdentifier`, `parentApplicationBundleIdentifier`, the title, whether artwork data is present and whether the position advances.
2. **Commands.** With the song still playing, run `likes.sh send 1` (pause), `send 0` (play), `send 4` (next) and `send 5` (previous), and note whether the iPhone's own screen follows or only the Mac's audio does. Then seek with the adapter's `seek` command and note the same.
3. **Handoff.** Start a song on the iPhone, bring the phone near the Mac and accept the Handoff in Music or Spotify, then run `rec handoff` and `cmds handoff`. Note which app reports it.
4. **Unconnected iPhone.** Play on the iPhone's own speaker or AirPods, with no AirPlay to the Mac, then run `rec unconnected` for 20 seconds. Note whether any line mentions the iPhone, and open Control Center on the Mac to see whether it shows the track.
5. **Priority.** While the AirPlay song plays, also play something locally in Music, run `rec mixed`, and open Warble to see which one `SourcePriority` follows.
6. Run `likes.sh stop` after each case.

Keep the `.jsonl` files worth keeping as fixtures under `Tests/WarbleModelTests/Playback/Fixtures`.

## Recommendation

Not decided yet. The choices are nothing, document the AirPlay case only, or build it as an opt-in extra, and they depend on what steps 1 to 4 show.
