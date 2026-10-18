#!/bin/bash
# Prints the Homebrew cask for a release, for Casks/warble.rb in LorcanChinnock/homebrew-tap.
# The release workflow runs it on every release; run it by hand to seed or repair the tap.
# Usage: homebrew-cask.sh <version, without the v> <path to Warble-v<version>.zip>
set -euo pipefail

version="$1"
sha256="$(shasum -a 256 "$2" | cut -d ' ' -f 1)"

cat <<EOF
cask "warble" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/LorcanChinnock/warble/releases/download/v#{version}/Warble-v#{version}.zip"
  name "Warble"
  desc "Music and media controls in the notch"
  homepage "https://warble.lorcanchinnock.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "Warble.app"

  uninstall quit: "dev.lorcan.Warble"

  zap trash: [
    "~/Library/Application Support/dev.lorcan.Warble",
    "~/Library/Caches/dev.lorcan.Warble",
    "~/Library/HTTPStorages/dev.lorcan.Warble",
    "~/Library/HTTPStorages/dev.lorcan.Warble.binarycookies",
    "~/Library/Preferences/dev.lorcan.Warble.plist",
  ]

  caveats <<~EOS
    Warble isn't notarized by Apple yet, so macOS blocks it the first time you open it.
    Open Warble and click Done, then click Open Anyway in
    System Settings > Privacy & Security and confirm. You only do this once.
    Steps with pictures: https://warble.lorcanchinnock.com/#install
  EOS
end
EOF
