#!/bin/sh
# Runs the tests with coverage and prints line coverage per file for WarbleModel and WarbleCore, lowest first. The app
# target has no tests, so it isn't measured. Extra arguments go to xcodebuild. PerfTests skip themselves.
# Usage: scripts/coverage.sh
set -eu
cd "$(dirname "$0")/.."

bundle=build/coverage.xcresult
rm -rf "$bundle"
scripts/xcodebuild.sh -scheme Warble -destination "platform=macOS,arch=$(uname -m)" -enableCodeCoverage YES \
    -resultBundlePath "$bundle" -quiet test "$@" >&2
json=build/coverage.json
xcrun xccov view --report --json "$bundle" > "$json"

python3 -I - "$json" <<'PY'
import json, sys

targets = {t["name"].removesuffix(".framework"): t for t in json.load(open(sys.argv[1]))["targets"]}
for name in ("WarbleModel", "WarbleCore"):
    target = targets.get(name)
    if target is None:
        print(f"{name}: no coverage")
        continue
    files = sorted(target["files"], key=lambda f: f["lineCoverage"])
    print(f"{name}: {target['coveredLines']}/{target['executableLines']} lines, {100 * target['lineCoverage']:.1f}%")
    for f in files:
        path = f["path"].split(f"/Sources/{name}/")[-1]
        print(f"  {100 * f['lineCoverage']:5.1f}%  {f['coveredLines']:4}/{f['executableLines']:<4}  {path}")
PY
