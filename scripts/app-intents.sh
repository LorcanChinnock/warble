#!/bin/bash
# Writes Metadata.appintents for the app's Shortcuts actions into the folder given. SwiftPM builds the intents but doesn't
# run Xcode's metadata step, and without that file Shortcuts and Spotlight never list them.
# Usage: scripts/app-intents.sh <resources folder>
set -euo pipefail
resources="$1"
# The folder the release build of the Warble target wrote its arm64 objects to, whichever build system SwiftPM used.
file_list="$(find .build -path '*elease*' -path '*arm64*' -name Warble.SwiftFileList | head -1)"
if [ -z "$file_list" ]; then
    echo "error: no release build of the Warble target to read the intents from." >&2
    find .build -name '*.SwiftFileList' >&2
    exit 1
fi
objects="$(dirname "$file_list")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
find "$objects" -name "*.swiftconstvalues" > "$work/const-values.txt"
if [ ! -s "$work/const-values.txt" ]; then
    echo "error: the build wrote no Swift constant values in $objects." >&2
    ls "$objects" >&2
    exit 1
fi
toolchain="$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")"
xcode_build="$(xcodebuild -version | awk '/Build version/ { print $3 }')"
xcrun appintentsmetadataprocessor \
    --output "$work/out" \
    --toolchain-dir "$toolchain" \
    --module-name Warble \
    --sdk-root "$(xcrun --show-sdk-path)" \
    --xcode-version "$xcode_build" \
    --platform-family macOS \
    --deployment-target 15.0 \
    --target-triple arm64-apple-macosx15.0 \
    --source-file-list "$objects/Warble.SwiftFileList" \
    --swift-const-vals-list "$work/const-values.txt" \
    --quiet-warnings
rm -rf "$resources/Metadata.appintents"
cp -R "$work/out/Metadata.appintents" "$resources/Metadata.appintents"
