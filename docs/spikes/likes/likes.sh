#!/bin/sh
# Spike tooling for #287. Builds a copy of the adapter whose `send` accepts any MediaRemote command,
# and `send 999` lists the commands the now playing app supports.
#
#   likes.sh rec NAME    record `stream --no-diff --micros` to out/NAME.jsonl in the background, ready to be a fixture
#   likes.sh cmds NAME   list supported commands to out/NAME-commands.txt and show the like-related ones
#   likes.sh send ID     send a MediaRemote command
#   likes.sh stop        stop recording
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
out="$here/out"
adapter="$out/adapter"
framework="$adapter/MediaRemoteAdapter.framework"

if [ ! -f "$framework/MediaRemoteAdapter" ]; then
    git -C "$repo" submodule update --init Vendor/mediaremote-adapter
    mkdir -p "$out"
    rm -rf "$adapter"
    cp -R "$repo/Vendor/mediaremote-adapter" "$adapter"
    patch -s -d "$adapter" -p1 < "$here/send-any-command.patch"
    mkdir -p "$framework"
    clang -dynamiclib -fobjc-arc -fvisibility=default -I"$adapter/include" -I"$adapter/src" \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        "$adapter"/src/adapter/*.m "$adapter/src/private/MediaRemote.m" "$adapter"/src/utility/*.m \
        -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
        -o "$framework/MediaRemoteAdapter"
    codesign -fs - "$framework/MediaRemoteAdapter"
fi

mra() { /usr/bin/perl "$adapter/bin/mediaremote-adapter.pl" "$framework" "$@"; }

case "${1:-}" in
    rec)
        mra stream --no-diff --micros --no-artwork > "$out/$2.jsonl" &
        echo "recording to $out/$2.jsonl" ;;
    cmds) mra send 999 | tee "$out/$2-commands.txt" | grep -E '^(2[0-3]|10[6-8])[[:space:]]' || true ;;
    send) mra send "$2" && echo "sent $2" ;;
    stop) pkill -f "$adapter/bin/mediaremote-adapter.pl" || true; echo stopped ;;
    *) sed -n '2,9p' "$0"; exit 1 ;;
esac
