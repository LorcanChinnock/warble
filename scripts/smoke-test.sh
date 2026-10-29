#!/bin/sh
# Launches a built app, checks it is still running after a few seconds and left no crash report, then quits it. This
# catches startup failures such as a bad entitlement, a missing resource or a Sparkle misconfiguration, which no unit
# test reaches. It drives no UI.
# Usage: scripts/smoke-test.sh [path to WarbleDev.app] (default build/WarbleDev.app)
set -eu

app=${1:-build/WarbleDev.app}
name=$(basename "$app" .app)
seconds=${SMOKE_TEST_SECONDS:-8}
reports="$HOME/Library/Logs/DiagnosticReports"

[ -x "$app/Contents/MacOS/$name" ] || { echo "No executable at $app/Contents/MacOS/$name"; exit 1; }
if pgrep -x "$name" >/dev/null; then
    echo "$name is already running; quit it first."
    exit 1
fi

started=$(mktemp)
trap 'rm -f "$started"; pkill -x "$name" 2>/dev/null || true' EXIT

"$app/Contents/MacOS/$name" &
pid=$!
sleep "$seconds"

if ! kill -0 "$pid" 2>/dev/null; then
    status=0
    wait "$pid" || status=$?
    echo "$name exited with status $status within ${seconds}s."
    sleep 5
    for report in "$reports/$name"*.ips; do
        [ -f "$report" ] && [ "$report" -nt "$started" ] && echo "Crash report: $report"
    done
    exit 1
fi

for report in "$reports/$name"*.ips; do
    if [ -f "$report" ] && [ "$report" -nt "$started" ]; then
        echo "$name left a crash report: $report"
        exit 1
    fi
done

kill "$pid"
wait "$pid" 2>/dev/null || true
echo "$name stayed up for ${seconds}s with no crash report."
