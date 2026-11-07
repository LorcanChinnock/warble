#!/bin/bash
# Archives a universal (Apple Silicon and Intel) Release app, as Product › Archive does, and copies it to build/. The
# archive, with the dSYMs that symbolicate a crash report, stays in build/<name>.xcarchive.
# Only WARBLE_RELEASE=1 (make dist) builds Warble.app, with the update feed. Every other build is WarbleDev.app, with its
# own name, bundle ID and executable and no feed, so it never replaces or answers for an installed release
# (Config/Warble.xcconfig).
set -euo pipefail
cd "$(dirname "$0")/.."

args=(-scheme Warble -configuration Release -destination generic/platform=macOS ARCHS="arm64 x86_64")
name=WarbleDev
if [ "${WARBLE_RELEASE:-}" = 1 ]; then
    name=Warble
    # A release builds exactly the versions in Package.resolved, so a dependency only changes through a reviewed bump.
    args+=(-onlyUsePackageVersionsFromResolvedFile WARBLE_DISTRIBUTION=YES)
    # A release signed ad hoc would reset every user's Automation permission on update, so it fails instead.
    identity="${WARBLE_SIGN_IDENTITY:-}"
    if [ -z "$identity" ] || [ "$identity" = "-" ] || ! security find-identity -p codesigning | grep -q "\"$identity\""; then
        echo "error: set WARBLE_SIGN_IDENTITY to the release signing identity; a release must not be signed ad hoc." >&2
        exit 1
    fi
fi

# The app's build phase builds mediaremote-adapter from the Vendor/mediaremote-adapter submodule (CONTRIBUTING.md ›
# Updating the adapter). A release must build the commit Warble pins.
adapter_src=Vendor/mediaremote-adapter
case "$(git submodule status "$adapter_src")" in
    -*)
        echo "error: $adapter_src is empty; run git submodule update --init." >&2
        exit 1
        ;;
    +*)
        if [ "${WARBLE_RELEASE:-}" = 1 ]; then
            echo "error: $adapter_src isn't at the commit Warble pins; run git submodule update." >&2
            exit 1
        fi
        echo "warning: $adapter_src isn't at the commit Warble pins; building it as it is." >&2
        ;;
esac

build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
archive="build/$name.xcarchive"
app="build/$name.app"

rm -rf "$archive" "$app"
scripts/xcodebuild.sh "${args[@]}" CURRENT_PROJECT_VERSION="$build_number" -archivePath "$archive" -quiet archive
ditto "$archive/Products/Applications/$name.app" "$app"
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number) for $(lipo -archs "$app/Contents/MacOS/$name")"
