#!/bin/bash
# Build Anear.app — a Dock-less macOS menu-bar accessory.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Anear.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Anear "$APP/Contents/MacOS/Anear"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Assets/MenuBarTemplate.png "$APP/Contents/Resources/MenuBarTemplate.png"
cp Assets/MenuBarTemplate@2x.png "$APP/Contents/Resources/MenuBarTemplate@2x.png"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Anear</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>dev.fahim.anear</string>
    <key>CFBundleName</key><string>Anear</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built: $APP"
echo "Run via: open $APP"
