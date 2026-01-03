#!/bin/bash
#
# Update Monitome icons from source images
#
# Usage: ./scripts/update-icons.sh [app-icon.png] [menubar-icon.png]
#
# If no args provided, looks for:
#   - icons/monitome-app.png (or latest monitome-v*.png)
#   - icons/monitome-menubar.png (or latest monitome-menubar-v*.png)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ICONS_DIR="$PROJECT_DIR/icons"
ASSETS_DIR="$PROJECT_DIR/Monitome/Assets.xcassets"

# Find source icons
if [ -n "$1" ]; then
    APP_ICON="$1"
else
    APP_ICON=$(ls -t "$ICONS_DIR"/monitome-v*.png 2>/dev/null | head -1 || ls "$ICONS_DIR"/monitome-app.png 2>/dev/null || echo "")
fi

if [ -n "$2" ]; then
    MENUBAR_ICON="$2"
else
    MENUBAR_ICON=$(ls -t "$ICONS_DIR"/monitome-menubar-v*.png 2>/dev/null | head -1 || ls "$ICONS_DIR"/monitome-menubar.png 2>/dev/null || echo "")
fi

# Validate
if [ -z "$APP_ICON" ] || [ ! -f "$APP_ICON" ]; then
    echo "Error: App icon not found. Provide path or place in icons/"
    exit 1
fi

if [ -z "$MENUBAR_ICON" ] || [ ! -f "$MENUBAR_ICON" ]; then
    echo "Error: Menu bar icon not found. Provide path or place in icons/"
    exit 1
fi

echo "App icon: $APP_ICON"
echo "Menu bar icon: $MENUBAR_ICON"

# Generate App Icons
echo "Generating app icons..."
APP_OUT="$ASSETS_DIR/AppIcon.appiconset"
mkdir -p "$APP_OUT"

sips -z 16 16 "$APP_ICON" --out "$APP_OUT/icon-16.png" >/dev/null
sips -z 32 32 "$APP_ICON" --out "$APP_OUT/icon-16@2x.png" >/dev/null
sips -z 32 32 "$APP_ICON" --out "$APP_OUT/icon-32.png" >/dev/null
sips -z 64 64 "$APP_ICON" --out "$APP_OUT/icon-32@2x.png" >/dev/null
sips -z 128 128 "$APP_ICON" --out "$APP_OUT/icon-128.png" >/dev/null
sips -z 256 256 "$APP_ICON" --out "$APP_OUT/icon-128@2x.png" >/dev/null
sips -z 256 256 "$APP_ICON" --out "$APP_OUT/icon-256.png" >/dev/null
sips -z 512 512 "$APP_ICON" --out "$APP_OUT/icon-256@2x.png" >/dev/null
sips -z 512 512 "$APP_ICON" --out "$APP_OUT/icon-512.png" >/dev/null
sips -z 1024 1024 "$APP_ICON" --out "$APP_OUT/icon-512@2x.png" >/dev/null

cat > "$APP_OUT/Contents.json" << 'EOF'
{
  "images" : [
    {"filename": "icon-16.png", "idiom": "mac", "scale": "1x", "size": "16x16"},
    {"filename": "icon-16@2x.png", "idiom": "mac", "scale": "2x", "size": "16x16"},
    {"filename": "icon-32.png", "idiom": "mac", "scale": "1x", "size": "32x32"},
    {"filename": "icon-32@2x.png", "idiom": "mac", "scale": "2x", "size": "32x32"},
    {"filename": "icon-128.png", "idiom": "mac", "scale": "1x", "size": "128x128"},
    {"filename": "icon-128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128"},
    {"filename": "icon-256.png", "idiom": "mac", "scale": "1x", "size": "256x256"},
    {"filename": "icon-256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256"},
    {"filename": "icon-512.png", "idiom": "mac", "scale": "1x", "size": "512x512"},
    {"filename": "icon-512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512"}
  ],
  "info" : {"author": "xcode", "version": 1}
}
EOF

# Generate Menu Bar Icons (24x24 for good visibility)
echo "Generating menu bar icons..."
MENU_OUT="$ASSETS_DIR/MenuBarIcon.imageset"
mkdir -p "$MENU_OUT"

sips -z 24 24 "$MENUBAR_ICON" --out "$MENU_OUT/icon-24.png" >/dev/null
sips -z 48 48 "$MENUBAR_ICON" --out "$MENU_OUT/icon-24@2x.png" >/dev/null

cat > "$MENU_OUT/Contents.json" << 'EOF'
{
  "images" : [
    {"filename": "icon-24.png", "idiom": "mac", "scale": "1x"},
    {"filename": "icon-24@2x.png", "idiom": "mac", "scale": "2x"}
  ],
  "info" : {"author": "xcode", "version": 1},
  "properties" : {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
EOF

echo "Done! Icons updated."
echo ""
echo "Next: Rebuild in Xcode (Cmd+Shift+K, then Cmd+B)"
