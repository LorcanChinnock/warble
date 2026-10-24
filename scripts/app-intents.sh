#!/bin/bash
# Writes Metadata.appintents for the app's Shortcuts actions into the folder given. SwiftPM builds the intents but doesn't
# run Xcode's metadata step, and without that file Shortcuts and Spotlight never list them.
# Usage: scripts/app-intents.sh <the Warble target's build folder for one architecture> <resources folder>
set -euo pipefail
objects="$1"
resources="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ls "$objects"/*.swiftconstvalues > "$work/const-values.txt"
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
