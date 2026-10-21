#!/bin/bash
# Measures the app's fast and idle paths on this Mac and checks them against the budgets in docs/performance.md.
# Drives an installed WarbleDev with the pointer, so it takes over the mouse for about four minutes, and needs:
#   - Accessibility permission for this terminal (moving the pointer, clicking the notch, finding Play/Pause),
#   - nothing playing when it starts, for the idle measurements.
# It quits any running WarbleDev, and the installed Warble too, since both draw in the notch, and reopens Warble at the end
# if it was running. The pointer goes back where it was.
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

# Budgets, about 1.5x the baselines in docs/performance.md. The idle and at-rest ones are absolute instead: no CPU, and
# wakeups only as often as macOS itself wakes the app, about one every 10 seconds, so any timer of 5 seconds or less
# fails. Empty means not measured: printed, not checked.
budget_launch_ms="205"
budget_idle_cpu="0.1"
budget_idle_wakeups="0.2"
budget_playing_cpu="0.5"
budget_playing_wakeups="0.3"
budget_memory_mb="26"
budget_hover_ms="55"
budget_click_ms="70"
budget_play_pause_ms="20"

work=$(mktemp -d "${TMPDIR:-/tmp}/warble-perf.XXXXXX")
started=$(date "+%Y-%m-%d %H:%M:%S")
input="$work/perf-input"
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

# CPU as a percentage of one core, and wakeups a second, over the next $1 seconds.
measure_cpu() {
  local cpu_before wakeups_before
  cpu_before=$(cpu_seconds)
  wakeups_before=$(wakeups)
  sleep "$1"
  cpu=$(python3 -c "print(round(($(cpu_seconds) - $cpu_before) / $1 * 100, 2))")
  wakeups_per_second=$(python3 -c "print(round(($(wakeups) - $wakeups_before) / $1, 2))")
}

# Milliseconds since the last keyboard or pointer input, the script's own included.
input_idle_ms() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF / 1000000); exit}'; }

# measure_cpu for $1 seconds while nobody uses the Mac. Using it, or switching apps, makes macOS wake every app, which
# would count as Warble's wakeups, so a measurement with input during it is taken again, up to three times. The
# script's own last input came before the wait that precedes this.
measure_quietly() {
  for _ in 1 2 3; do
    measure_cpu "$1"
    if [ "$(input_idle_ms)" -ge $(($1 * 1000)) ]; then
      return
    fi
    echo "Someone used the Mac while $2 was measured, which wakes every app. Measuring it again. Leave the Mac alone." >&2
  done
  cpu=""
  wakeups_per_second=""
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
release_was_running=0
pgrep -x Warble >/dev/null && release_was_running=1
# shellcheck disable=SC2329 # Called by the EXIT trap.
clean_up() {
  # shellcheck disable=SC2086 # Two words, x and y.
  "$input" move $pointer_before || true
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
  sleep 2
done
launch_ms=$(signposts Ready | python3 -c '
import json, re, sys
for line in sys.stdin:
    entry = json.loads(line)
    match = re.search(r"launch ms=(\d+)", entry.get("eventMessage", ""))
    if entry.get("signpostType") == "event" and match:
        print(match.group(1))' | median)
[ "$(ps -o comm= -p "$(pid)")" = "$app/Contents/MacOS/$executable" ] || { echo "The running WarbleDev isn't $app" >&2; exit 1; }

# Idle: nothing playing and the pointer away from the notch, for a minute. It starts 20 seconds after launch, once macOS
# has finished with the new process: AppKit and Launch Services wake it a few times in its first seconds, with timers of
# their own that fire once.
read -r housing_x housing_y <<<"$("$input" housing)"
away_x=$housing_x
away_y=$((housing_y + 400))
"$input" move "$away_x" "$away_y"
sleep 20
measure_quietly 60 "idle"
idle_cpu=$cpu
idle_wakeups=$wakeups_per_second

# Playing: the preview track, which plays without a player, so the runs repeat. The adapter doesn't run, so this is the
# notch's own cost: the art, the title and the play-state bars at 8 fps.
quit "$executable"
open -g -a "$app" --args -notchPreviewState resting
sleep 20
measure_quietly 30 "playing at rest"
playing_cpu=$cpu
playing_wakeups=$wakeups_per_second
memory=$(memory_mb)

# Hover → expanded: from the end of the hover delay to the first frame of the morph, ten times.
for _ in $(seq 10); do
  "$input" move "$housing_x" "$housing_y"
  sleep 1
  "$input" move "$away_x" "$away_y"
  sleep 1.2
done

# Click → expanded: from the click to the first frame of the morph, ten times. Moving off the notch closes it again.
for _ in $(seq 10); do
  "$input" click "$housing_x" "$housing_y"
  sleep 1
  "$input" move "$away_x" "$away_y"
  sleep 1.2
done

# Play/pause: from a click on the button to the first frame that shows the new state, ten times, so it ends playing.
"$input" move "$housing_x" "$housing_y"
sleep 1
read -r button_x button_y <<<"$("$input" find "$bundle_id" Pause)"
for _ in $(seq 10); do
  "$input" click "$button_x" "$button_y"
  sleep 0.6
done
"$input" move "$away_x" "$away_y"
sleep 2

hover_ms=$(times Expand hover | median)
click_ms=$(times Expand click | median)
play_pause_ms=$(times Play/pause click | median)

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
row "Idle CPU, nothing playing" "$idle_cpu" % "$budget_idle_cpu"
row "Wakeups, nothing playing" "$idle_wakeups" "a second" "$budget_idle_wakeups"
row "CPU playing, at rest" "$playing_cpu" % "$budget_playing_cpu"
row "Wakeups playing, at rest" "$playing_wakeups" "a second" "$budget_playing_wakeups"
row "Memory playing" "$memory" MB "$budget_memory_mb"
row "Hover delay end → expanded" "$hover_ms" ms "$budget_hover_ms"
row "Click → expanded" "$click_ms" ms "$budget_click_ms"
row "Click → play/pause shown" "$play_pause_ms" ms "$budget_play_pause_ms"
echo
exit $failed
