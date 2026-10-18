#!/bin/sh
# Fails on patterns that have caused bugs.
set -eu
cd "$(dirname "$0")/.."

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
