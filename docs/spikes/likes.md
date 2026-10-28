# Spike: liking the current track from the notch

Findings for [#287](https://github.com/LorcanChinnock/warble/issues/287). Checked on macOS 27.0.1. The recommendation is a heart for Music only, set through AppleScript; streamed catalog tracks and stations are still untested (see [Recommendation](#recommendation)).

## Tooling

`docs/spikes/likes/likes.sh` builds a copy of the adapter with `send-any-command.patch` applied, so `send` takes any MediaRemote command ID, and `send 999` lists the commands the now playing app supports, with whether each is enabled and its options. It needs only the Command Line Tools, not CMake. Output goes to `docs/spikes/likes/out/`, which git ignores.

## Found so far

### MediaRemote command IDs

`MRMediaRemoteCopyCommandDescription` names them. The adapter's `MediaRemote.h` labels 0x6A to 0x6D as like, ban and wish list, but those IDs are other commands:

| ID | Command |
| --- | --- |
| 20 | RateTrack |
| 21 | LikeTrack |
| 22 | DislikeTrack |
| 23 | BookmarkTrack |
| 106 | BanTrack |
| 107 | AddTrackToWishList |
| 108 | RemoveTrackFromWishList |

A player lists the commands it takes through `MRMediaRemoteGetSupportedCommandsForOrigin`. Each entry says whether it's enabled, and for like and dislike an `IsActive` flag, which could serve as the like state.

### Music

Tested with a local file added to the library, because this account has no Apple Music subscription.

- The stream carries no `isLiked`, `supportsIsLiked`, `isBanned` or `isInWishList`.
- Music lists 21 as "Like" ("Play More Like This") and 22 as "Never Play" ("Play Less Like This"), both disabled for a library track, with `IsActive` 0. Sending 21, 22 or 106 reports success and changes nothing.
- AppleScript reads and sets `favorited` and `disliked` reliably. Setting `favorited` doesn't change the stream or `IsActive`, so a favourite and MediaRemote's like aren't the same thing.
- Reading `loved` fails with error -10001 (descriptor type mismatch). `favorited` has replaced it.

Still open for Music: a streamed catalog track that isn't in the library, and a station, where "Play More Like This" may be enabled.

### Spotify, Podcasts and YouTube

Tested with Spotify, Podcasts, and YouTube in Safari and in Chrome, each playing alone.

| Player | Commands 21 and 22 listed | `send 21` and `send 22` | Like keys in the stream |
| --- | --- | --- | --- |
| Spotify | No | Report success, change nothing | None |
| Podcasts | No | Report success, change nothing | None |
| YouTube in Safari | No | Report success, change nothing | None |
| YouTube in Chrome | No | Report success, change nothing | None |

- Spotify lists only the playback commands. Podcasts adds skip, playback rate, sleep timer and queue commands. Both YouTube players list play, pause and seek (Chrome also stop), and Safari adds skip.
- Saving an episode and following the show in Podcasts, and liking, disliking and subscribing on YouTube, added no stream lines that carry a like, dislike or ban key.
- Spotify's "Add to Liked Songs" wasn't pressed while recording, because Spotify has no AppleScript for it. The stream carried no like keys before that.

So MediaRemote can't read or set a like for any of these players. Only a player's own scripting could, and only Music's AppleScript is confirmed to work.

## Recommendation

**Build a heart for Music only, and nothing for the other players.**

- **Music.** AppleScript reads and sets `favorited` reliably, so the heart can show whether the current track is a favourite and toggle it. Warble would read `favorited` once when the card expands, with no timer, and write it on a click. The setting starts off in Settings, and the heart appears only when Music is the now playing app.
- **Spotify, Podcasts and YouTube.** None of them lists a like command or reports a like in the stream, and Spotify has no AppleScript property for one. Only page scripting could reach YouTube's 👍, and the browser spike ([#333](https://github.com/LorcanChinnock/warble/issues/333)) ruled that route out as not native. So these players get no heart.
- **Not covered by the tests.** This account has no Apple Music subscription, so `favorited` was only checked on a library track. Before building, check a streamed catalog track that isn't in the library and a station, and whether a heart should also read as "Play More Like This" there. If `favorited` fails on a streamed track, the heart should hide for that track and not show an error.

### Other actions

- **Dislike.** Music's `disliked` reads and sets the same way, but no other player has a dislike to match, and it changes what Music recommends, which makes a mis-click costly. Leave it out; the heart is the only like action.
- **Follow and subscribe.** MediaRemote has no follow or subscribe command, and the Podcasts and YouTube streams carried nothing a follow could use. YouTube would need page scripting, which is ruled out above. Leave both out.

## Test plan

Run each player alone, so it's the now playing app. Replace NAME with `music`, `spotify`, `podcasts`, `yt-safari` or `yt-chrome`.

1. Start playback, then run `docs/spikes/likes/likes.sh rec NAME`.
2. After 5 seconds, run `docs/spikes/likes/likes.sh cmds NAME`.
3. Like the track in the player, wait 5 seconds, unlike it and wait 5 seconds again.
4. If the player has a dislike, dislike and undo it the same way.
5. Run `docs/spikes/likes/likes.sh send 21` and note whether the player shows a like, then do the same with `send 22`.
6. Run `docs/spikes/likes/likes.sh stop` and note what happened in steps 3 and 5.

Per player:

- **Music.** Needs an Apple Music subscription. Play a catalog song that isn't in the library and use Favorite in the player bar or the ⋯ menu. For question 5, check `favorited` with `osascript -e 'tell application "Music" to get favorited of current track'` before and after. Then play a station and repeat step 2.
- **Spotify.** Like with "Add to Liked Songs" in the player bar. There's no dislike for songs.
- **Podcasts.** Treat Save Episode as the like. In step 3 also follow and unfollow the show.
- **YouTube in Safari, then in Chrome.** Signed in. Use 👍 and 👎, and in step 3 also subscribe and unsubscribe.

Keep the `.jsonl` files worth keeping as fixtures under `Tests/WarbleModelTests/Playback/Fixtures`.
