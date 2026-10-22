# Demo player

A made-up music player for recording Warble. It publishes four invented tracks to macOS as now-playing information, with art it draws itself, so Warble's screenshots and recordings carry no one else's songs or artwork. It plays no sound. It isn't part of Warble: `make build`, `make test` and `make lint` don't touch it, and Warble reads it through the adapter like any other player.

For a still with no player at all, launch Warble with `-notchPreviewState resting`. Use this player when a recording needs a real one, such as skipping tracks or the idle card after a pause.

1. Quit any other player that is playing, and quit the installed Warble (`pkill -x Warble`) if you are recording `WarbleDev`.
2. Build and open the demo:

   ```sh
   docs/demo/build.sh
   open docs/demo/build/WarbleDemo.app
   ```

3. Open Warble. It follows the demo like any player: the next, previous, play/pause and seek buttons all work.

To start somewhere else, pass `--args`:

```sh
open docs/demo/build/WarbleDemo.app --args --track 3 --paused
```

- `--track N` starts on track 1 to 4.
- `--paused` starts paused, for the idle card.

Quit it with `pkill -x WarbleDemo`. The tracks and their art are fixed, so a re-shoot lines up with the last one. Record with Shot and keep the clips in `docs/media`, where `site/scripts/media.sh` picks them up.
