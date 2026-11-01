#!/bin/bash
# Removes Warble from this Mac.
#
#   curl -fsSL https://warble.lorcanchinnock.com/uninstall.sh | bash
#   curl -fsSL https://warble.lorcanchinnock.com/uninstall.sh | bash -s -- --everything
#
# By default this quits Warble and moves the app to the Trash, and keeps your settings and the permission you gave it
# to control Music, Spotify and browsers, so installing Warble again picks up where you left off. With --everything it
# also removes those and the small cache from checking for updates.
#
# Environment: WARBLE_UNINSTALL_APPS (the folder holding Warble.app) and WARBLE_UNINSTALL_HOME (the home folder) exist
# so scripts/test-uninstall.sh can run this against a local folder. With WARBLE_UNINSTALL_HOME set, the script touches
# only files under it and leaves the real preferences and permissions alone.
set -euo pipefail

EVERYTHING=0
HOME_DIR="${WARBLE_UNINSTALL_HOME:-$HOME}"
TESTING=0
[ -n "${WARBLE_UNINSTALL_HOME:-}" ] && TESTING=1
ID="dev.lorcan.Warble"

say() { printf '%s\n' "$*"; }
fail() { printf 'Warble was not removed: %s\n' "$*" >&2; exit 1; }

# Finds Warble.app in the folder from WARBLE_UNINSTALL_APPS, or else /Applications and then ~/Applications (where the
# installer puts it when /Applications isn't writable).
find_app() {
    local dir
    for dir in "${WARBLE_UNINSTALL_APPS:-/Applications}" "$HOME_DIR/Applications"; do
        if [ -d "$dir/Warble.app" ]; then
            printf '%s\n' "$dir/Warble.app"
            return 0
        fi
    done
    return 1
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --everything) EVERYTHING=1 ;;
            *) fail "unknown option $arg" ;;
        esac
    done
    [ "$(uname -s)" = "Darwin" ] || fail "Warble only runs on a Mac."

    app=""
    app="$(find_app)" || true

    if [ -n "$app" ] && [ "$TESTING" = 0 ] && pgrep -x Warble > /dev/null 2>&1; then
        say "Quitting Warble..."
        osascript -e "tell application id \"$ID\" to quit" > /dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x Warble > /dev/null 2>&1 || break
            sleep 0.5
        done
    fi

    if [ "$EVERYTHING" = 1 ]; then
        # macOS can only look up Warble's permissions while the app is still installed, so this comes before the Trash.
        if [ "$TESTING" = 0 ]; then
            tccutil reset All "$ID" > /dev/null 2>&1 || say "Couldn't clear Warble's permissions. Remove Warble in System Settings › Privacy & Security › Automation."
            defaults delete "$ID" > /dev/null 2>&1 || true
        fi
        rm -f "$HOME_DIR/Library/Preferences/$ID.plist" "$HOME_DIR/Library/HTTPStorages/$ID.binarycookies"
        rm -rf "$HOME_DIR/Library/Application Support/$ID" "$HOME_DIR/Library/Caches/$ID" "$HOME_DIR/Library/HTTPStorages/$ID"
        say "Removed Warble's settings, permissions and cache."
    fi

    if [ -n "$app" ]; then
        trash="$HOME_DIR/.Trash"
        mkdir -p "$trash"
        name="Warble.app"
        [ -e "$trash/$name" ] && name="Warble $(date +%H.%M.%S).app"
        mv "$app" "$trash/$name" || fail "couldn't move $app to the Trash."
        say "Moved Warble to the Trash."
    else
        say "Warble.app isn't in Applications, so there was no app to remove."
    fi

    if [ "$EVERYTHING" = 0 ]; then
        say "Kept your settings and permissions. Run again with --everything to remove them too."
    fi
    say "If Warble was set to open at login, remove it in System Settings › General › Login Items & Extensions."
}

# Everything runs from this one call, so a download cut off halfway can't run a partial script.
main "$@"
