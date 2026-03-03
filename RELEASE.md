# Release Guide

## Quick Release

```bash
# 1. Bump version
#    - Monitome.xcodeproj → MARKETING_VERSION
#    - activity-agent/package.json → version
#    Commit: git commit -am "chore: bump version to X.Y.Z"

# 2. Build, sign, notarize, and create DMG
APPLE_ID=swairshah@gmail.com \
APP_PASSWORD="$(grep APPLE_APP_PASSWORD ~/.env | cut -d= -f2)" \
./scripts/build-release.sh X.Y.Z

# 3. Tag and push
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin main
git push origin vX.Y.Z

# 4. Create GitHub release
gh release create vX.Y.Z dist/Monitome-X.Y.Z.dmg \
    --title "vX.Y.Z" \
    --generate-notes

# 5. Update Homebrew tap (SHA256 is printed by build script)
cd ~/work/projects/homebrew-tap
# Edit Casks/monitome.rb: update version and sha256
git add Casks/monitome.rb
git commit -m "Update monitome to vX.Y.Z"
git push
```

## Detailed Steps

### 1. Bump Version

Update version in two places:
- `Monitome.xcodeproj` → Build Settings → `MARKETING_VERSION`
- `activity-agent/package.json` → `"version"`

Commit the version bump:
```bash
git commit -am "chore: bump version to X.Y.Z"
```

### 2. Build Release

```bash
./scripts/build-release.sh X.Y.Z
```

This will:
- Build the activity-agent as a universal binary (ARM64 + x86_64)
- Build the Pi binary as a universal binary
- Build the Swift app (Release configuration, universal)
- Bundle activity-agent and Pi into the .app
- Code sign everything (inside-out: frameworks → binaries → bundle)
- Create a DMG
- Notarize with Apple (if `APPLE_ID` and `APP_PASSWORD` are set)
- Staple the notarization ticket
- Print the SHA256

To notarize in the same step:
```bash
APPLE_ID=swairshah@gmail.com \
APP_PASSWORD="$(grep APPLE_APP_PASSWORD ~/.env | cut -d= -f2)" \
./scripts/build-release.sh X.Y.Z
```

Or notarize separately:
```bash
xcrun notarytool submit dist/Monitome-X.Y.Z.dmg \
    --apple-id "swairshah@gmail.com" \
    --team-id "8B9YURJS4G" \
    --password "$(grep APPLE_APP_PASSWORD ~/.env | cut -d= -f2)" \
    --wait

xcrun stapler staple dist/Monitome-X.Y.Z.dmg
```

### 3. Tag and Push

```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

### 4. Create GitHub Release

```bash
gh release create vX.Y.Z dist/Monitome-X.Y.Z.dmg \
    --title "vX.Y.Z" \
    --generate-notes
```

Or manually at https://github.com/swairshah/Monitome/releases/new

### 5. Update Homebrew Tap

```bash
cd ~/work/projects/homebrew-tap

# Edit Casks/monitome.rb with new version and SHA256 from build output
# Then:
git add Casks/monitome.rb
git commit -m "Update monitome to vX.Y.Z"
git push
```

### 6. Verify Installation

```bash
brew update
brew upgrade --cask monitome

# Or fresh install:
brew tap swairshah/tap
brew install --cask monitome
```

## Troubleshooting

### Notarization fails
```bash
# Check submission log
xcrun notarytool log SUBMISSION_ID \
    --apple-id "swairshah@gmail.com" \
    --team-id "8B9YURJS4G" \
    --password "$(grep APPLE_APP_PASSWORD ~/.env | cut -d= -f2)"
```

### Notarization stuck
- Check status: `xcrun notarytool history --apple-id EMAIL --team-id TEAM`
- Apple status: https://developer.apple.com/system-status/

### Build fails
- Full xcodebuild log is saved to `dist/xcodebuild.log`
- Check signing identity: `security find-identity -v -p codesigning`
