## macOS App Build & Distribution Guide

```
PROJECT_DIR=~/work/projects/Monitome
PROJECT_NAME=Monitome
BUNDLE_ID=swair.Monitome
SIGNING_IDENTITY="Developer ID Application: Swair Rajesh Shah (8B9YURJS4G)"
OUTPUT_DIR=~/Desktop/Monitome
```

---
## Step 1: Build the app

### Clean and build for release
xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
  -scheme "$PROJECT_NAME" \
  -configuration Release \
  -archivePath "$OUTPUT_DIR/$PROJECT_NAME.xcarchive" \
  archive

## Step 2: Export the archive

### Create export options plist
```
cat > "$OUTPUT_DIR/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>8B9YURJS4G</string>
</dict>
</plist>
EOF
```

### Export
```
xcodebuild -exportArchive \
  -archivePath "$OUTPUT_DIR/$PROJECT_NAME.xcarchive" \
  -exportPath "$OUTPUT_DIR/Export" \
  -exportOptionsPlist "$OUTPUT_DIR/ExportOptions.plist"
```

## Step 3: Sign the app (if not already signed by export)

### Remove extended attributes
```
xattr -cr "$OUTPUT_DIR/Export/$PROJECT_NAME.app"
```

### Sign with hardened runtime + timestamp
```
codesign --deep --force --options runtime --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$OUTPUT_DIR/Export/$PROJECT_NAME.app"
```

### Verify
```
codesign -vvv --deep --strict "$OUTPUT_DIR/Export/$PROJECT_NAME.app"
```

## Step 4: Create DMG

### Create temp folder with app + Applications shortcut
```
mkdir -p "$OUTPUT_DIR/dmg-contents"
cp -R "$OUTPUT_DIR/Export/$PROJECT_NAME.app" "$OUTPUT_DIR/dmg-contents/"
ln -sf /Applications "$OUTPUT_DIR/dmg-contents/Applications"
```

### Create DMG
```
rm -f "$OUTPUT_DIR/$PROJECT_NAME.dmg"
hdiutil create -volname "$PROJECT_NAME" \
  -srcfolder "$OUTPUT_DIR/dmg-contents" \
  -ov -format UDZO \
  "$OUTPUT_DIR/$PROJECT_NAME.dmg"
```

### Cleanup temp folder
```
rm -rf "$OUTPUT_DIR/dmg-contents"
```

### Sign DMG
```
codesign --force --timestamp \
  --sign "$SIGNING_IDENTITY" \
  "$OUTPUT_DIR/$PROJECT_NAME.dmg"
```

## Step 5: Notarize

```
xcrun notarytool submit "$OUTPUT_DIR/$PROJECT_NAME.dmg" \
  --keychain-profile notary-profile \
  --wait
```

## Step 6: Staple (after notarization succeeds)

```
xcrun stapler staple "$OUTPUT_DIR/$PROJECT_NAME.dmg"
```

## Step 7: Verify

```
spctl -a -vv "$OUTPUT_DIR/$PROJECT_NAME.dmg"
```
