#!/bin/bash
# Measures the app's fast and idle paths on this Mac and checks them against the budgets in docs/performance.md.
# Drives an installed WarbleDev with the pointer, so it takes over the mouse for about a minute (PERF_FULL=1: six and a half minutes), and needs:
#   - Accessibility permission for this terminal (moving the pointer, clicking the notch, finding Play/Pause),
#   - nothing playing when it starts, for the idle measurements,
#   - for the waveform measurement, macOS's permission to record system audio for WarbleDev (Screen & System Audio Recording).
# It quits any running WarbleDev, and the installed Warble too, since both draw in the notch, and reopens Warble at the end
# if it was running. The pointer goes back where it was.
# By default it checks the latencies, which take a minute: launch, hover, click, play/pause and memory. PERF_FULL=1 (make
# perf-app-full) adds the idle, playing and waveform CPU and wakeups, which each need a minute of watching, for six and a
# half minutes in all. Run the full one before a release.
# Usage: scripts/perf.sh [path/to/WarbleDev.app]   (default /Applications/WarbleDev.app, which make app installs)
set -euo pipefail

app="${1:-/Applications/WarbleDev.app}"
[ -d "$app" ] || { echo "No app at $app. Run make app first." >&2; exit 1; }
# Absolute and resolved, as ps reports the running executable.
app=$(cd "$app" && pwd -P)
cd "$(dirname "$0")/.."
bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist")
executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist")
resources="$app/Contents/Resources"
full="${PERF_FULL:-0}"
if [ "$full" = 1 ]; then
  pause=1 gap=1.2 launch_gap=2
else
  pause=0.6 gap=0.6 launch_gap=0.5
fi

# Budgets, about 1.5x the baselines in docs/performance.md. The idle and at-rest ones are absolute instead: no CPU, and
# no wakeups in the median 10 seconds, so any timer of 10 seconds or less fails. Empty means not
# measured: printed, not checked.
budget_launch_ms="205"
budget_idle_cpu="0.1"
budget_idle_wakeups="0"
budget_playing_cpu="0.5"
budget_playing_wakeups="0"
budget_waveform_cpu="0.5"
budget_memory_mb="33"
budget_hover_ms="55"
budget_click_ms="70"
budget_play_pause_ms="20"

work=$(mktemp -d "${TMPDIR:-/tmp}/warble-perf.XXXXXX")
started=$(date "+%Y-%m-%d %H:%M:%S")
input="$work/perf-input"
tone="$work/tone.wav"
python3 - "$tone" <<'PY'
# Eight seconds of tones that move across all four bands, so every bar has something to follow.
import math, struct, sys, wave
rate = 44100
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(2)
    out.setsampwidth(2)
    out.setframerate(rate)
    frames = bytearray()
    for n in range(rate * 8):
        t = n / rate
        sample = sum(0.15 * math.sin(2 * math.pi * f * t) * (0.6 + 0.4 * math.sin(2 * math.pi * (i + 1) * 0.5 * t))
                     for i, f in enumerate((110, 440, 1760, 5000)))
        frames += struct.pack("<hh", *([int(sample * 32767)] * 2))
    out.writeframes(bytes(frames))
PY
swiftc -O -o "$input" scripts/perf-input.swift 2>/dev/null || { echo "Couldn't compile scripts/perf-input.swift" >&2; exit 1; }

# Nothing may be playing, or the idle measurements would measure playback. The adapter prints null when nothing is.
playing=$(/usr/bin/perl "$resources/mediaremote-adapter.pl" "$resources/MediaRemoteAdapter.framework" "$resources/MediaRemoteAdapterTestClient" get 2>/dev/null || true)
if [ "$playing" != "null" ]; then
  echo "Something is playing, or was paused a moment ago. Quit the app that's playing, then run this again." >&2
  exit 1
fi
"$input" trusted || { echo "This terminal needs Accessibility permission (System Settings › Privacy & Security › Accessibility)." >&2; exit 1; }

signposts() { # name → ndjson lines of that signpost from this app since the script started
  /usr/bin/log show --signpost --start "$started" --style ndjson \
    --predicate "subsystem == \"$bundle_id\" AND category == \"perf\" AND signpostName == \"$1\"" 2>/dev/null
}

# name cause → milliseconds from each end message of that signpost with that cause, such as "click ms=12.3", one per line.
times() {
  signposts "$1" | python3 -c '
import json, re, sys
for line in sys.stdin:
    entry = json.loads(line)
    match = re.match(sys.argv[1] + r" ms=([\d.]+)", entry.get("eventMessage", ""))
    if entry.get("signpostType") == "end" and match:
        print(match.group(1))' "$2"
}

median() { python3 -c 'import sys,statistics; v=[float(x) for x in sys.stdin.read().split()]; print(round(statistics.median(v), 1) if v else "")'; }

quit() { # executable
  pkill -x "$1" || true
  while pgrep -x "$1" >/dev/null; do sleep 0.1; done
}

pid() { pgrep -x "$executable" | head -1; }

# The app and every process under it: the adapter's stream runs in Perl, and its CPU counts as Warble's.
family() {
  local parent=$1
  echo "$parent"
  for child in $(pgrep -P "$parent"); do family "$child"; done
}

# Seconds of CPU the app and its children have used, and their wakeups: the times a thread of theirs started running
# again, such as for a timer. top's own wakeup column stays at 0 for a process that wakes twice a second, but its
# context switches count each one.
cpu_seconds() {
  # shellcheck disable=SC2046 # One pid per word.
  ps -o time= -p $(family "$(pid)" | paste -sd, -) | python3 -c '
import sys
total = 0
for line in sys.stdin.read().split():
    days, _, clock = line.rpartition("-")
    parts = [float(p) for p in clock.split(":")]
    total += float(days or 0) * 86400 + sum(value * 60 ** index for index, value in enumerate(reversed(parts)))
print(total)'
}
wakeups() {
  local total=0
  for each in $(family "$(pid)"); do
    count=$(top -l 1 -stats csw -pid "$each" | tail -1 | tr -dc '0-9')
    total=$((total + ${count:-0}))
  done
  echo "$total"
}

# CPU as a percentage of one core over the next $1 seconds, and the wakeups in the median 10-second slice of them. A
# timer of 10 seconds or less wakes the app in every slice. macOS wakes every app when you switch apps or type, and
# keep-awake apps such as Caffeine fake input every minute or two, but those land in a slice or two, which the median
# leaves out.
measure_cpu() {
  local cpu_before counts="" before after
  cpu_before=$(cpu_seconds)
  before=$(wakeups)
  for _ in $(seq $(($1 / 10))); do
    sleep 10
    after=$(wakeups)
    counts="$counts $((after - before))"
    before=$after
  done
  cpu=$(python3 -c "print(round(($(cpu_seconds) - $cpu_before) / $1 * 100, 2))")
  wakeups_median=$(echo "$counts" | python3 -c 'import sys,statistics; print(statistics.median_low(int(x) for x in sys.stdin.read().split()))')
  wakeup_slices=$counts
}

memory_mb() {
  footprint -p "$(pid)" 2>/dev/null | python3 -c '
import re, sys
match = re.search(r"Footprint: ([\d.]+) (B|KB|MB|GB)", sys.stdin.read())
scale = {"B": 1 / 2**20, "KB": 1 / 1024, "MB": 1, "GB": 1024}
print(round(float(match.group(1)) * scale[match.group(2)]) if match else "")'
}

# Put back whatever the script changed, however it ends.
pointer_before=$("$input" pointer)
volume_before=$(osascript -e 'output muted of (get volume settings)')
tone_player=""
release_was_running=0
pgrep -x Warble >/dev/null && release_was_running=1
# shellcheck disable=SC2329 # Called by the EXIT trap.
clean_up() {
  # shellcheck disable=SC2086 # Two words, x and y.
  "$input" move $pointer_before || true
  if [ -n "$tone_player" ]; then
    kill "$tone_player" 2>/dev/null || true
    pkill -x afplay || true
    wait "$tone_player" 2>/dev/null || true
  fi
  osascript -e "set volume output muted $volume_before" || true
  quit "$executable"
  if [ "$release_was_running" = 1 ]; then
    open -g -a Warble || true
  fi
  rm -rf "$work"
}
trap clean_up EXIT
quit Warble

# Launch → ready: process start to the notch drawn and shortcuts registered, from the app's "Ready" event, three launches.
ready_count() { signposts Ready | grep -c '"signpostType":"event"' || true; }
for _ in 1 2 3; do
  quit "$executable"
  before=$(ready_count)
  open -g -a "$app"
  ready=0
  for _ in $(seq 50); do
    if [ "$(ready_count)" -gt "$before" ]; then
      ready=1
      break
    fi
    sleep 0.4
  done
  [ "$ready" = 1 ] || { echo "WarbleDev didn't report Ready within 20 s of launching" >&2; exit 1; }
  sleep "$launch_gap"
done
launch_ms=$(signposts Ready | python3 -c '
import json, re, sys
for line in sys.stdin:
    entry = json.loads(line)
    match = re.search(r"launch ms=(\d+)", entry.get("eventMessage", ""))
    if entry.get("signpostType") == "event" and match:
        print(match.group(1))' | median)
[ "$(ps -o comm= -p "$(pid)")" = "$app/Contents/MacOS/$executable" ] || { echo "The running WarbleDev isn't $app" >&2; exit 1; }

# Idle: nothing playing and the pointer away from the notch, for a minute. It starts 40 seconds after launch, once macOS
# has finished with the new process: AppKit and Launch Services wake it a few times in its first minute, with timers of
# their own that fire once.
read -r housing_x housing_y <<<"$("$input" housing)"
away_x=$housing_x
away_y=$((housing_y + 400))
"$input" move "$away_x" "$away_y"
idle_cpu="" idle_wakeups="" idle_slices="" playing_cpu="" playing_wakeups="" playing_slices="" waveform_cpu=""
if [ "$full" = 1 ]; then
  sleep 40
  measure_cpu 60
  idle_cpu=$cpu
  idle_wakeups=$wakeups_median
  idle_slices=$wakeup_slices
fi

# Playing: the preview track, which plays without a player, so the runs repeat. The adapter doesn't run, so CPU and
# wakeups at rest, measured after the notch has opened and closed, are the notch's own cost: the art, the title and the
# play-state bars at 8 fps.
quit "$executable"
open -g -a "$app" --args -notchPreviewState resting
sleep 5

# Hover → expanded: from the end of the hover delay to the first frame of the morph, ten times.
for _ in $(seq 10); do
  "$input" move "$housing_x" "$housing_y"
  sleep "$pause"
  "$input" move "$away_x" "$away_y"
  sleep "$gap"
done

# Click → expanded: from the click to the first frame of the morph, ten times. Moving off the notch closes it again.
for _ in $(seq 10); do
  "$input" click "$housing_x" "$housing_y"
  sleep "$pause"
  "$input" move "$away_x" "$away_y"
  sleep "$gap"
done

# Play/pause: from a click on the button to the first frame that shows the new state, ten times, so it ends playing.
"$input" move "$housing_x" "$housing_y"
sleep 1
read -r button_x button_y <<<"$("$input" find "$bundle_id" Pause)"
for _ in $(seq 10); do
  "$input" click "$button_x" "$button_y"
  sleep 0.4
done
"$input" move "$away_x" "$away_y"
if [ "$full" = 1 ]; then
  sleep 10
  measure_cpu 60
  playing_cpu=$cpu
  playing_wakeups=$wakeups_median
  playing_slices=$wakeup_slices
fi
memory=$(memory_mb)

# Waveform: the same preview track with "Move the bars with the sound" on, and a tone playing in a loop, muted, which the
# tap still hears. The bars then follow the sound, 15 frames a second, and that is the cost this measures. If macOS
# refuses the tap, the app turns the setting off and says so in waveformRefused. The launch argument stands in for the
# setting without saving it.
if [ "$full" = 1 ]; then
  quit "$executable"
  defaults delete "$bundle_id" waveformRefused 2>/dev/null || true
  open -g -a "$app" --args -notchPreviewState resting -waveform YES
  osascript -e 'set volume output muted true'
  (while true; do afplay "$tone"; done) &
  tone_player=$!
  sleep 15
  if [ "$(defaults read "$bundle_id" waveformRefused 2>/dev/null || echo 0)" = 1 ]; then
    echo "macOS refused WarbleDev the system audio recording permission, so the waveform wasn't measured." >&2
  else
    measure_cpu 60
    waveform_cpu=$cpu
  fi
fi

# Reading the log is slow, so the three queries run side by side. A bare wait would also wait for the tone player.
times Expand hover | median >"$work/hover" &
queries=$!
times Expand click | median >"$work/click" &
queries="$queries $!"
times Play/pause click | median >"$work/play_pause" &
queries="$queries $!"
# shellcheck disable=SC2086 # One pid per word.
wait $queries
hover_ms=$(cat "$work/hover")
click_ms=$(cat "$work/click")
play_pause_ms=$(cat "$work/play_pause")

failed=0
row() { # name value unit budget
  local verdict="not budgeted"
  if [ -z "$2" ]; then
    verdict="NOT MEASURED"
    failed=1
  elif [ -n "$4" ]; then
    if python3 -c "import sys; sys.exit(0 if float('$2') <= float('$4') else 1)"; then verdict="ok (budget $4)"; else verdict="OVER (budget $4)"; failed=1; fi
  fi
  printf "%-28s %8s %-10s %s\n" "$1" "$2" "$3" "$verdict"
}
echo
row "Launch → ready" "$launch_ms" ms "$budget_launch_ms"
if [ "$full" = 1 ]; then
  row "Idle CPU, nothing playing" "$idle_cpu" % "$budget_idle_cpu"
  row "Wakeups, nothing playing" "$idle_wakeups" "per 10 s" "$budget_idle_wakeups"
  row "CPU playing, at rest" "$playing_cpu" % "$budget_playing_cpu"
  row "Wakeups playing, at rest" "$playing_wakeups" "per 10 s" "$budget_playing_wakeups"
  row "CPU with the waveform" "$waveform_cpu" % "$budget_waveform_cpu"
fi
row "Memory playing, after use" "$memory" MB "$budget_memory_mb"
row "Hover delay end → expanded" "$hover_ms" ms "$budget_hover_ms"
row "Click → expanded" "$click_ms" ms "$budget_click_ms"
row "Click → play/pause shown" "$play_pause_ms" ms "$budget_play_pause_ms"
[ "$full" = 1 ] && echo "Wakeups in each 10 s, nothing playing:$idle_slices. Playing at rest:$playing_slices."
[ "$full" = 1 ] || echo "Latencies only. PERF_FULL=1 (make perf-app-full) adds CPU and wakeups."
echo
exit $failed
