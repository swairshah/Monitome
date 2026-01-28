#!/bin/bash
set -e

# Configuration
APP_NAME="Monitome"
VERSION="${1:-0.1.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="$APP_NAME-$VERSION.dmg"

echo "Building $APP_NAME v$VERSION..."

# Clean
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 1. Build the activity-agent binary
echo "Building activity-agent..."
cd "$PROJECT_DIR/activity-agent"
npm install --silent
bun build src/cli.ts --compile --outfile dist/activity-agent

# 2. Build the Swift app (Release)
echo "Building Swift app..."
cd "$PROJECT_DIR"
xcodebuild -project Monitome.xcodeproj \
    -scheme Monitome \
    -configuration Release \
    -derivedDataPath "$DIST_DIR/build" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -20

# 3. Copy the app
APP_PATH="$DIST_DIR/build/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

cp -R "$APP_PATH" "$DIST_DIR/"

# 4. Copy activity-agent into the app bundle
echo "Bundling activity-agent..."
cp "$PROJECT_DIR/activity-agent/dist/activity-agent" "$DIST_DIR/$APP_NAME.app/Contents/MacOS/"
chmod +x "$DIST_DIR/$APP_NAME.app/Contents/MacOS/activity-agent"

# 5. Create DMG
echo "Creating DMG..."
cd "$DIST_DIR"

# Create a temporary directory for DMG contents
mkdir -p dmg_contents
cp -R "$APP_NAME.app" dmg_contents/
ln -s /Applications dmg_contents/Applications

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder dmg_contents \
    -ov -format UDZO \
    "$DMG_NAME"

# Cleanup
rm -rf dmg_contents
rm -rf build

# Calculate SHA256
SHA256=$(shasum -a 256 "$DMG_NAME" | cut -d' ' -f1)

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo "DMG: $DIST_DIR/$DMG_NAME"
echo "SHA256: $SHA256"
echo ""
echo "To install manually:"
echo "  open $DIST_DIR/$DMG_NAME"
echo ""
echo "For Homebrew cask, use:"
echo "  sha256 \"$SHA256\""
echo "  url \"https://github.com/YOUR_USER/Monitome/releases/download/v$VERSION/$DMG_NAME\""
