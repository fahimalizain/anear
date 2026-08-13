#!/bin/bash
# Rebuilds the binary icon assets.
#
#   scripts/make-icons.sh                        # rebuild AppIcon.icns only
#   scripts/make-icons.sh <menu-bar-source.jpg>  # also re-key the menu-bar
#                                                # templates from a white-
#                                                # background source (black
#                                                # glyph), e.g. the xAI
#                                                # grok-imagine-image-2.0
#                                                # menubar-1.png
set -euo pipefail
cd "$(dirname "$0")/.."

# App icon: icns from the committed 1024x1024 AppIcon.png (16...1024 + @2x).
mkdir -p Assets/AppIcon.iconset
for s in 16 32 128 256 512 1024; do
    sips -z "$s" "$s" Assets/AppIcon.png --out "Assets/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
done
for s in 16 32 128 256 512; do
    d=$((s * 2))
    sips -z "$d" "$d" Assets/AppIcon.png --out "Assets/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
rm -rf Assets/AppIcon.iconset
echo "rebuilt Assets/AppIcon.icns"

# Menu-bar templates: key white -> transparent, black -> opaque glyph.
if [ "$#" -ge 1 ]; then
    swift scripts/make-menu-bar-icons.swift "$1" Assets
    cp Assets/MenuBarTemplate.png Assets/MenuBarTemplate@2x.png Sources/Anear/Resources/
fi
