#!/bin/sh
# Runs the tests with coverage and prints line coverage per file for WarbleModel and WarbleCore, lowest first. The app
# target has no tests, so it isn't measured. Extra arguments go to `swift test`. PerfTests are skipped.
# Usage: scripts/coverage.sh
set -eu

swift test --enable-code-coverage --skip PerfTests "$@" >&2
json=$(swift test --show-codecov-path)

python3 -I - "$json" <<'EOF'
import json, sys

files = json.load(open(sys.argv[1]))["data"][0]["files"]
rows = []
for file in files:
    name = file["filename"]
    for target in ("WarbleModel", "WarbleCore"):
        if f"/Sources/{target}/" in name:
            lines = file["summary"]["lines"]
            rows.append((target, name.split(f"/Sources/{target}/")[1], lines["covered"], lines["count"]))

for target in ("WarbleModel", "WarbleCore"):
    own = sorted((r for r in rows if r[0] == target), key=lambda r: r[2] / max(r[3], 1))
    covered, count = sum(r[2] for r in own), sum(r[3] for r in own)
    print(f"{target}: {covered}/{count} lines, {100 * covered / max(count, 1):.1f}%")
    for _, path, c, n in own:
        print(f"  {100 * c / max(n, 1):5.1f}%  {c:4}/{n:<4}  {path}")
EOF
