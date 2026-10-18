#!/bin/bash
# Builds a release binary and assembles a signed app in build/.
# Only WARBLE_RELEASE=1 (make dist) builds Warble.app, with the update feed. Every other build is WarbleDev.app, with its own
# name, bundle ID, executable and warble-dev:// scheme and no feed, so it never replaces or answers for an installed release.
set -euo pipefail
cd "$(dirname "$0")/.."

# A release builds exactly the versions in Package.resolved, so a dependency only changes through a reviewed bump.
resolved=()
if [ "${WARBLE_RELEASE:-}" = 1 ]; then
    resolved=(--force-resolved-versions)
fi

# A universal binary: build each architecture alone, then join the slices with lipo.
# Both builds can write to the same folder, so each slice is copied out before the next build.
universal="build/universal"
rm -rf "$universal"
mkdir -p "$universal"
for arch in arm64 x86_64; do
    swift build -c release --arch "$arch" ${resolved[@]+"${resolved[@]}"}
    bin_path="$(swift build -c release --arch "$arch" --show-bin-path)"
    mkdir "$universal/$arch"
    cp "$bin_path/Warble" "$universal/$arch/"
done
for exe in Warble; do
    lipo -create "$universal/arm64/$exe" "$universal/x86_64/$exe" -output "$universal/$exe"
    lipo -info "$universal/$exe"
done
binary="$universal/Warble"

# Since macOS 15.4, MediaRemote answers only Apple-signed processes, so the now-playing source runs
# ungive/mediaremote-adapter's script under /usr/bin/perl, which loads the adapter's framework. Both come from the
# Vendor/mediaremote-adapter submodule (CONTRIBUTING.md › Updating the adapter) and are only bundled, never linked.
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
if ! command -v cmake >/dev/null; then
    echo "error: building the adapter needs CMake; install it with brew install cmake." >&2
    exit 1
fi
# CMake would otherwise target the Mac doing the build, and the framework wouldn't load on older macOS.
# The adapter's CMakeLists.txt builds both architectures itself.
adapter_build=build/mediaremote-adapter
cmake -S "$adapter_src" -B "$adapter_build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
cmake --build "$adapter_build" --parallel

if [ "${WARBLE_RELEASE:-}" = 1 ]; then
    name=Warble
else
    name=WarbleDev
fi
app="build/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary" "$app/Contents/MacOS/$name"
ditto "$bin_path/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# Sparkle's MIT and the adapter's BSD licences require their notices in copies of the app. Settings › About opens this file.
cp Resources/Acknowledgements.txt "$app/Contents/Resources/Acknowledgements.txt"
# The now-playing source runs `/usr/bin/perl <script> <framework> <test client> <command>` with these absolute paths.
# The test client is only for the `test` command, which fakes playback to check the adapter still works.
cp "$adapter_src/bin/mediaremote-adapter.pl" "$app/Contents/Resources/mediaremote-adapter.pl"
ditto "$adapter_build/MediaRemoteAdapter.framework" "$app/Contents/Resources/MediaRemoteAdapter.framework"
cp "$adapter_build/MediaRemoteAdapterTestClient" "$app/Contents/Resources/MediaRemoteAdapterTestClient"
# One .lproj folder per language, where Bundle.main finds the app's strings and the permission prompts' text.
for catalog in Resources/*.xcstrings; do
    xcrun xcstringstool compile "$catalog" --output-directory "$app/Contents/Resources"
done
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
if [ "$name" = WarbleDev ]; then
    dev_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Resources/Info.plist).dev"
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleIdentifier $dev_id" \
        -c "Set :CFBundleName WarbleDev" \
        -c "Set :CFBundleDisplayName WarbleDev" \
        -c "Set :CFBundleExecutable WarbleDev" \
        -c "Set :CFBundleURLTypes:0:CFBundleURLName $dev_id" \
        -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 warble-dev" \
        -c "Delete :SUFeedURL" \
        "$app/Contents/Info.plist"
fi

identity="${WARBLE_SIGN_IDENTITY:-Warble Dev}"
# A release signed ad hoc would reset every user's Automation permission on update, so it fails instead.
if [ "${WARBLE_RELEASE:-}" = 1 ] && { [ "$identity" = "-" ] || ! security find-identity -p codesigning | grep -q "\"$identity\""; }; then
    echo "error: signing identity '$identity' not found; a release must not be signed ad hoc." >&2
    exit 1
fi
if [ "$identity" != "-" ] && ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "warning: signing identity '$identity' not found; signing ad-hoc. Permissions macOS granted the app reset on every build." >&2
    identity="-"
fi
# Sign Sparkle's nested helpers inside-out, then the app. Sparkle's docs advise against --deep.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    codesign --force --sign "$identity" --preserve-metadata=entitlements "$sparkle/$part"
done
codesign --force --sign "$identity" "$app/Contents/Frameworks/Sparkle.framework"
# The adapter's build signs it ad hoc; sign it again with the app's identity, before the app seals its resources.
codesign --force --sign "$identity" "$app/Contents/Resources/MediaRemoteAdapterTestClient"
codesign --force --sign "$identity" "$app/Contents/Resources/MediaRemoteAdapter.framework"
codesign --force --sign "$identity" "$app"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
echo "Built $app $version ($build_number) for $(lipo -archs "$app/Contents/MacOS/$name")"
