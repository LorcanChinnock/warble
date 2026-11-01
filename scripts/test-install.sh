#!/bin/bash
# Runs site/public/install.sh against a local folder standing in for the GitHub release, and checks that a good
# download installs, a tampered one is refused, and a failed install leaves the previous copy in place.
set -euo pipefail
cd "$(dirname "$0")/.."

script="$PWD/site/public/install.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if command -v shellcheck > /dev/null; then
    shellcheck "$script"
else
    echo "shellcheck isn't installed; skipping it."
fi

release="$work/release"
dest="$work/Applications"
mkdir -p "$release" "$dest" "$work/app/Warble.app/Contents/MacOS"
echo "new" > "$work/app/Warble.app/Contents/MacOS/Warble"
ditto -c -k --keepParent "$work/app/Warble.app" "$release/Warble-v9.9.9.zip"
(cd "$release" && shasum -a 256 Warble-v9.9.9.zip > SHA256SUMS)

run() { WARBLE_INSTALL_BASE="file://$release" WARBLE_INSTALL_DEST="$dest" "$script" --no-open; }

# 1. A good download installs.
run > /dev/null
[ "$(cat "$dest/Warble.app/Contents/MacOS/Warble")" = "new" ] || { echo "FAIL: Warble.app wasn't installed"; exit 1; }
if xattr -lr "$dest/Warble.app" | grep -q com.apple.quarantine; then echo "FAIL: the installed app is quarantined"; exit 1; fi

# 2. An install over an older copy replaces it without keeping its files.
echo "stale" > "$dest/Warble.app/Contents/stale.txt"
run > /dev/null
[ ! -e "$dest/Warble.app/Contents/stale.txt" ] || { echo "FAIL: a file from the old copy survived"; exit 1; }

# 3. A download that doesn't match its checksum is refused, and the installed copy is untouched.
echo "tampered" > "$work/app/Warble.app/Contents/MacOS/Warble"
rm "$release/Warble-v9.9.9.zip"
ditto -c -k --keepParent "$work/app/Warble.app" "$release/Warble-v9.9.9.zip"
if run > "$work/out.txt" 2>&1; then echo "FAIL: a tampered download was installed"; exit 1; fi
grep -q "checksum" "$work/out.txt" || { echo "FAIL: no checksum message"; cat "$work/out.txt"; exit 1; }
[ "$(cat "$dest/Warble.app/Contents/MacOS/Warble")" = "new" ] || { echo "FAIL: the good copy was overwritten"; exit 1; }

echo "install.sh: all checks passed"
