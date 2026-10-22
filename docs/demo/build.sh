#!/bin/sh
# Builds build/WarbleDemo.app. The adapter names a player by its bundle identifier, so the demo needs a bundle.
set -eu
cd "$(dirname "$0")"
swift build -c release
app=build/WarbleDemo.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/WarbleDemo "$app/Contents/MacOS/WarbleDemo"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.lorcan.WarbleDemo</string>
  <key>CFBundleName</key><string>Warble Demo</string>
  <key>CFBundleExecutable</key><string>WarbleDemo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built $app"
