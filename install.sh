#!/bin/zsh
# Builds Courier.app from source into ~/Applications and installs rimg into ~/.local/bin.
# Building locally means Gatekeeper won't block it, so no Developer ID is needed.
set -euo pipefail
cd "${0:A:h}"

APP="$HOME/Applications/Courier.app"
mkdir -p "$HOME/.local/bin" "$APP/Contents/MacOS"

install -m 755 rimg rex-paste "$HOME/.local/bin/"
swiftc -O main.swift Core.swift MenuBar.swift Windows.swift -o "$APP/Contents/MacOS/Courier"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp icons/*.svg "$APP/Contents/Resources/"

# App icon: render at 1024px, then build every size macOS wants.
tmp=$(mktemp -d)
swift make-icon.swift "$tmp/icon.png"
mkdir "$tmp/AppIcon.iconset"
for px in 16 32 128 256 512; do
  sips -z $px $px "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$tmp/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$tmp"
codesign -s - --force "$APP"

pkill -x Courier 2>/dev/null || true
# Courier used to be called Drop.
pkill -x Drop 2>/dev/null || true
rm -rf "$HOME/Applications/Drop.app"
open "$APP"
echo "Installed $APP. Look for the tray icon in your menu bar."
