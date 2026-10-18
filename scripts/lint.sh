#!/bin/sh
# Fails on patterns that have caused bugs.
set -eu
cd "$(dirname "$0")/.."

hits=$(grep -rnE 'NSHostingView\(rootView:|NSHostingController\(' Sources | grep -v 'Sources/Warble/Design/HostingView.swift' || true)
if [ -n "$hits" ]; then
    echo "Use NSView(hosting:) instead; a plain hosting view crashes when content changes under a visible window:"
    echo "$hits"
    exit 1
fi

hits=$(grep -rnE '@AppStorage[( ]|AppStorage\(' Sources || true)
if [ -n "$hits" ]; then
    echo "Use @Setting instead; @AppStorage catches up an update late, so views mixing it with other state show combinations that never existed:"
    echo "$hits"
    exit 1
fi

# WarbleModel builds and tests on Linux, where only Foundation and the standard library exist. The Linux build is the
# backstop; this names the cause first.
hits=$(find Sources/WarbleModel Tests/WarbleModelTests -name '*.swift' -exec awk '
    /^(@testable )?import / && !/^(@testable )?import (Foundation|Synchronization|Testing|WarbleModel)$/ &&
        !(/^import CoreGraphics$/ && prev == "#if canImport(CoreGraphics)") { print FILENAME ":" FNR ": " $0 }
    { prev = $0 }' {} +)
if [ -n "$hits" ]; then
    echo "WarbleModel runs on Linux: import only Foundation, or CoreGraphics inside #if canImport(CoreGraphics). Apple-only code goes in WarbleCore:"
    echo "$hits"
    exit 1
fi

# macOS jobs queue, since the free plan runs only 5 at once.
hits=$(awk '/runs-on:.*macos/ && prev !~ /# macOS: / { print FILENAME ":" FNR ": " $0 } { prev = $0 }' .github/workflows/*.yml)
if [ -n "$hits" ]; then
    echo "Put a '# macOS: <reason>' comment above each macOS runs-on, saying why the job can't run on Linux:"
    echo "$hits"
    exit 1
fi

# SwiftUI holds a single tap until the double-click interval passes, so every click lags by up to half a second.
hits=$(grep -rnE 'onTapGesture\(count: *[2-9]' Sources || true)
if [ -n "$hits" ]; then
    echo "Don't pair onTapGesture(count: 2) with a single-tap gesture; every single click waits out the double-click interval (Shot #452). Use one onTapGesture and read NSApp.currentEvent?.clickCount:"
    echo "$hits"
    exit 1
fi
