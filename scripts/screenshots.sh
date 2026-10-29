#!/bin/zsh
# Renders the README screenshots into docs/screenshots from demo devices and history.
# It runs a copy of Courier under its own app ID, so your real settings are never read or changed.
set -euo pipefail
cd "${0:A:h}/.."

./install.sh >/dev/null   # makes sure ~/Applications/Courier.app (icons, Info.plist) is current
tmp=$(mktemp -d)
cp -R "$HOME/Applications/Courier.app" "$tmp/CourierShots.app"
plutil -replace CFBundleIdentifier -string ai.reducto.courier.screenshots "$tmp/CourierShots.app/Contents/Info.plist"
cp scripts/screenshots.swift "$tmp/main.swift"   # top-level code has to live in main.swift
swiftc -O Core.swift MenuBar.swift Windows.swift "$tmp/main.swift" -o "$tmp/CourierShots.app/Contents/MacOS/Courier"
codesign -s - --force "$tmp/CourierShots.app"
mkdir -p docs/screenshots
"$tmp/CourierShots.app/Contents/MacOS/Courier" "$PWD/docs/screenshots"
defaults delete ai.reducto.courier.screenshots 2>/dev/null || true
rm -rf "$tmp"
echo "Wrote docs/screenshots/"
