#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/NotchLyrics.app"
CONFIG="${1:-release}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/NotchLyricsApp"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchLyrics"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>                  <string>NotchLyrics</string>
  <key>CFBundleDisplayName</key>           <string>NotchLyrics</string>
  <key>CFBundleIdentifier</key>            <string>com.local.NotchLyrics</string>
  <key>CFBundleVersion</key>               <string>1.0</string>
  <key>CFBundleShortVersionString</key>    <string>1.0</string>
  <key>CFBundlePackageType</key>           <string>APPL</string>
  <key>CFBundleExecutable</key>            <string>NotchLyrics</string>
  <key>LSMinimumSystemVersion</key>        <string>14.0</string>
  <key>LSUIElement</key>                   <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>NotchLyrics reads the currently playing track from Spotify to display synced lyrics.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Built $APP"
echo "    Run: open $APP"
