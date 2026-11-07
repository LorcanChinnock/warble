#!/bin/sh
# Runs xcodebuild on Warble.xcodeproj with the repository's defaults, so make, CI and the release build the same way,
# with Xcode even when only the Command Line Tools are selected. It builds into build/DerivedData ($DERIVED_DATA), apart
# from Xcode's own folder: Xcode 27 can leave a test bundle unsigned when both build into one. It signs with
# WARBLE_SIGN_IDENTITY when that's set. Otherwise the project signs with "Warble Dev" (scripts/make-dev-cert.sh), and
# when that identity is missing, as on CI, this signs ad hoc instead, so the build still works but permissions macOS
# granted the app reset on every build.
# Usage: scripts/xcodebuild.sh <xcodebuild arguments>
set -eu
cd "$(dirname "$0")/.."

if xcode-select -p | grep -q CommandLineTools; then
    if [ -d /Applications/Xcode.app ]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo "error: building Warble needs Xcode, and only the Command Line Tools are installed. Install Xcode from the App Store." >&2
        exit 1
    fi
fi

has_identity() {
    security find-identity -p codesigning | grep -q "\"$1\""
}

if [ -n "${WARBLE_SIGN_IDENTITY:-}" ]; then
    set -- "$@" CODE_SIGN_IDENTITY="$WARBLE_SIGN_IDENTITY"
elif [ ! -f Config/Local.xcconfig ] && ! has_identity "Warble Dev"; then
    echo "warning: signing identity 'Warble Dev' not found; signing ad hoc. Run scripts/make-dev-cert.sh so permissions such as Automation survive rebuilds." >&2
    set -- "$@" CODE_SIGN_IDENTITY=-
fi

derived="${DERIVED_DATA:-build/DerivedData}"
status=0
xcodebuild -project Warble.xcodeproj -derivedDataPath "$derived" "$@" || status=$?

# Xcode registers every app it builds with Launch Services, so Spotlight, Launchpad and Open at login could find these
# copies rather than the WarbleDev you installed or are running from Xcode. Unregister them.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
find "$derived/Build" -maxdepth 6 -name "*.app" -path "*Products*" -prune 2>/dev/null | while read -r app; do
    "$lsregister" -u "$app" 2>/dev/null || true
done
exit "$status"
