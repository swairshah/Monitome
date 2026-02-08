#!/bin/bash
set -e

# Configuration
APP_NAME="Monitome"
VERSION="${1:-0.1.0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="$APP_NAME-$VERSION.dmg"

# Signing identity (change if different)
SIGN_IDENTITY="Developer ID Application: Swair Rajesh Shah (8B9YURJS4G)"
TEAM_ID="8B9YURJS4G"

# For notarization - set these env vars or pass as args
APPLE_ID="${APPLE_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"  # App-specific password from appleid.apple.com

echo "Building $APP_NAME v$VERSION..."

# Clean
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 1. Build the activity-agent binary (Universal: ARM64 + x86_64)
echo "Building activity-agent (universal binary)..."
cd "$PROJECT_DIR/activity-agent"
npm install --silent 2>/dev/null || true

# Build for both architectures
echo "  Building for ARM64..."
bun build src/cli.ts --compile --target=bun-darwin-arm64 --outfile dist/activity-agent-arm64
echo "  Building for x86_64..."
bun build src/cli.ts --compile --target=bun-darwin-x64 --outfile dist/activity-agent-x64
echo "  Creating universal binary..."
lipo -create -output dist/activity-agent dist/activity-agent-arm64 dist/activity-agent-x64
rm dist/activity-agent-arm64 dist/activity-agent-x64

# Build TypeScript (includes extension)
echo "Building extension..."
npm run build

# 2. Build Pi binary (Universal: ARM64 + x86_64)
echo "Building Pi binary (universal binary)..."
PI_BUILD_DIR="$DIST_DIR/pi-build"
rm -rf "$PI_BUILD_DIR"
mkdir -p "$PI_BUILD_DIR"

# Get pi package location (from npm global or nvm)
PI_PKG_DIR=$(node -e "console.log(require.resolve('@mariozechner/pi-coding-agent/package.json').replace('/package.json', ''))" 2>/dev/null || echo "")
if [ -z "$PI_PKG_DIR" ] || [ ! -d "$PI_PKG_DIR" ]; then
    # Fallback to nvm location
    PI_PKG_DIR="$HOME/.nvm/versions/node/v22.16.0/lib/node_modules/@mariozechner/pi-coding-agent"
fi

if [ ! -d "$PI_PKG_DIR" ]; then
    echo "Error: Pi package not found. Install with: npm i -g @mariozechner/pi-coding-agent"
    exit 1
fi

echo "Using Pi from: $PI_PKG_DIR"
cp -r "$PI_PKG_DIR"/* "$PI_BUILD_DIR/"
cd "$PI_BUILD_DIR"

# Build for both architectures
echo "  Building for ARM64..."
bun build dist/cli.js --compile --target=bun-darwin-arm64 --outfile pi-arm64
echo "  Building for x86_64..."
bun build dist/cli.js --compile --target=bun-darwin-x64 --outfile pi-x64
echo "  Creating universal binary..."
lipo -create -output pi pi-arm64 pi-x64
rm pi-arm64 pi-x64

# Copy theme files (required at runtime)
mkdir -p "$PI_BUILD_DIR/theme"
cp "$PI_PKG_DIR/dist/modes/interactive/theme"/*.json "$PI_BUILD_DIR/theme/"

# 2. Build the Swift app (Release, Universal binary)
echo "Building Swift app (universal binary)..."
cd "$PROJECT_DIR"

# Temporarily hide the activity-agent binary so Xcode's copy script phase
# is a no-op — we handle copying + signing ourselves below.
AGENT_BINARY="$PROJECT_DIR/activity-agent/dist/activity-agent"
if [ -f "$AGENT_BINARY" ]; then
    mv "$AGENT_BINARY" "$AGENT_BINARY.tmp"
fi

xcodebuild -project Monitome.xcodeproj \
    -scheme Monitome \
    -configuration Release \
    -derivedDataPath "$DIST_DIR/build" \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    clean build \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    2>&1 | grep -E "(error:|warning:|BUILD|Signing)" || true

# Restore the activity-agent binary
if [ -f "$AGENT_BINARY.tmp" ]; then
    mv "$AGENT_BINARY.tmp" "$AGENT_BINARY"
fi

# 3. Copy the app
APP_PATH="$DIST_DIR/build/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

cp -R "$APP_PATH" "$DIST_DIR/"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

# 4. Copy activity-agent into the app bundle
echo "Bundling activity-agent..."
cp "$PROJECT_DIR/activity-agent/dist/activity-agent" "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/activity-agent"

# Remove any stray copies in Resources (Xcode might copy them there)
rm -f "$APP_BUNDLE/Contents/Resources/activity-agent"
rm -f "$APP_BUNDLE/Contents/Resources/pi"

# 4b. Copy Pi binary and extension into the app bundle
echo "Bundling Pi..."
cp "$PI_BUILD_DIR/pi" "$APP_BUNDLE/Contents/MacOS/"
chmod +x "$APP_BUNDLE/Contents/MacOS/pi"

# Copy theme files to Resources and symlink from MacOS (Pi looks relative to binary)
mkdir -p "$APP_BUNDLE/Contents/Resources/pi-theme"
cp "$PI_BUILD_DIR/theme"/*.json "$APP_BUNDLE/Contents/Resources/pi-theme/"
ln -s ../Resources/pi-theme "$APP_BUNDLE/Contents/MacOS/theme"

# Copy package.json to Resources and symlink (Pi reads version from it)
cp "$PI_BUILD_DIR/package.json" "$APP_BUNDLE/Contents/Resources/"
ln -s ../Resources/package.json "$APP_BUNDLE/Contents/MacOS/package.json"

# Copy bundled extension (self-contained, no external imports except better-sqlite3)
mkdir -p "$APP_BUNDLE/Contents/Resources/extensions/monitome-search"
cp "$PROJECT_DIR/activity-agent/dist/extension-bundle.js" "$APP_BUNDLE/Contents/Resources/extensions/monitome-search/index.js"

# Sign inside-out: inner components first, then main binary, then bundle

# 5. Sign all frameworks/dylibs with hardened runtime
echo "Signing frameworks..."
find "$APP_BUNDLE/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm +111 \) -exec \
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" {} \; 2>/dev/null || true

# 6. Sign activity-agent WITH hardened runtime AND JIT entitlements
echo "Signing activity-agent binary (with JIT entitlements)..."
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    --entitlements "$PROJECT_DIR/activity-agent/entitlements.plist" \
    "$APP_BUNDLE/Contents/MacOS/activity-agent"

# 6b. Sign Pi binary WITH hardened runtime AND JIT entitlements
echo "Signing Pi binary (with JIT entitlements)..."
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    --entitlements "$PROJECT_DIR/activity-agent/entitlements.plist" \
    "$APP_BUNDLE/Contents/MacOS/pi"

# 7. Sign the main app binary
echo "Signing main app binary..."
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE/Contents/MacOS/Monitome"

# 8. Sign the app bundle (top-level, preserves individual signatures)
echo "Signing app bundle..."
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"

# Verify signature
echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -3

# 7. Create DMG
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

# Sign the DMG too
codesign --force --sign "$SIGN_IDENTITY" "$DMG_NAME"

# Cleanup temp files
rm -rf dmg_contents
rm -rf build

# 8. Notarize (if credentials provided)
if [ -n "$APPLE_ID" ] && [ -n "$APP_PASSWORD" ]; then
    echo ""
    echo "Submitting for notarization..."
    xcrun notarytool submit "$DMG_NAME" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait
    
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG_NAME"
else
    echo ""
    echo "⚠️  Skipping notarization (APPLE_ID and APP_PASSWORD not set)"
    echo "   To notarize, run:"
    echo "   APPLE_ID=you@email.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx ./scripts/build-release.sh $VERSION"
fi

# Calculate SHA256
SHA256=$(shasum -a 256 "$DMG_NAME" | cut -d' ' -f1)

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo "DMG: $DIST_DIR/$DMG_NAME"
echo "SHA256: $SHA256"
echo ""
echo "For Homebrew cask update:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
