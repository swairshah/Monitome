# Release Guide

## Quick Release

```bash
# 1. Build the release DMG
./scripts/build-release.sh 0.1.0

# 2. Create GitHub release and upload DMG
gh release create v0.1.0 dist/Monitome-0.1.0.dmg --title "v0.1.0" --notes "Initial release"

# 3. Update Homebrew tap with the SHA256 from build output
```

## Manual Steps

### 1. Build Release

```bash
./scripts/build-release.sh 0.1.0
```

This will:
- Build the activity-agent (Bun compiled binary)
- Build the Swift app (Release configuration)
- Bundle activity-agent into the .app
- Create a DMG
- Output the SHA256

### 2. Create GitHub Release

1. Go to https://github.com/swairshah/Monitome/releases/new
2. Tag: `v0.1.0`
3. Title: `v0.1.0`
4. Upload: `dist/Monitome-0.1.0.dmg`
5. Publish

Or use GitHub CLI:
```bash
gh release create v0.1.0 dist/Monitome-0.1.0.dmg --title "v0.1.0" --notes "Initial release"
```

### 3. Update Homebrew Tap

Copy `homebrew/monitome.rb` to your tap repo and update the SHA256:

```bash
# Clone your tap
cd ~/work/projects
git clone https://github.com/swairshah/homebrew-tap.git
cd homebrew-tap

# Copy and update the formula
cp ../Monitome/homebrew/monitome.rb Casks/monitome.rb

# Edit Casks/monitome.rb and replace PLACEHOLDER_SHA256 with actual SHA256

# Commit and push
git add Casks/monitome.rb
git commit -m "Add monitome cask v0.1.0"
git push
```

### 4. Test Installation

```bash
# Install
brew install --cask swairshah/tap/monitome

# Or if tap not added yet
brew tap swairshah/tap
brew install --cask monitome
```

## Code Signing & Notarization (Optional but Recommended)

For distribution without Gatekeeper warnings:

### 1. Sign the App

```bash
# Sign with Developer ID
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    dist/Monitome.app

# Sign the activity-agent binary specifically
codesign --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    dist/Monitome.app/Contents/MacOS/activity-agent
```

### 2. Notarize

```bash
# Create zip for notarization
ditto -c -k --keepParent dist/Monitome.app dist/Monitome.zip

# Submit for notarization
xcrun notarytool submit dist/Monitome.zip \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --password "app-specific-password" \
    --wait

# Staple the notarization ticket
xcrun stapler staple dist/Monitome.app
```

### 3. Then Create DMG

```bash
# Create DMG from notarized app
hdiutil create -volname "Monitome" \
    -srcfolder dist/Monitome.app \
    -ov -format UDZO \
    dist/Monitome-0.1.0.dmg
```

## Version Bumping

Update version in:
1. `Monitome.xcodeproj` (MARKETING_VERSION)
2. `activity-agent/package.json`
3. `homebrew/monitome.rb`
