# Development & Release Guide

## Build & Run

```bash
open Monitome.xcodeproj
# Cmd+R to build and run
```

## Release Process

### 1. Archive

In Xcode:
1. Set scheme to Release: **Product → Scheme → Edit Scheme → Run → Release**
2. **Product → Archive**
3. Wait for archive to complete

### 2. Export & Notarize

In Organizer (Window → Organizer):
1. Select the archive
2. **Distribute App**
3. **Direct Distribution**
4. **Upload** (sends to Apple for notarization)
5. Wait for notarization (1-30 min)
6. Once complete, **Export** the notarized app

### 3. Create DMG

```bash
# Create staging folder
mkdir -p ~/Desktop/Monitome-dmg
cp -r /path/to/exported/Monitome.app ~/Desktop/Monitome-dmg/

# Create DMG
hdiutil create -volname "Monitome" -srcfolder ~/Desktop/Monitome-dmg -ov -format UDZO ~/Desktop/Monitome-1.0.0.dmg

# Clean up
rm -rf ~/Desktop/Monitome-dmg

# Get SHA256 for Homebrew cask
shasum -a 256 ~/Desktop/Monitome-1.0.0.dmg
```

### 4. GitHub Release

```bash
git add .
git commit -m "Release v1.0.0"
git tag v1.0.0
git push && git push --tags

gh release create v1.0.0 ~/Desktop/Monitome-1.0.0.dmg --title "v1.0.0" --notes "Release notes here"
```

### 5. Update Homebrew Cask

In your `homebrew-tap` repo, update `Casks/monitome.rb`:

```ruby
cask "monitome" do
  version "1.0.0"
  sha256 "YOUR_SHA256_HERE"

  url "https://github.com/swairshah/Monitome/releases/download/v#{version}/Monitome-#{version}.dmg"
  name "Monitome"
  desc "Periodic screenshot capture and analysis for macOS"
  homepage "https://github.com/swairshah/Monitome"

  app "Monitome.app"
end
```

```bash
git add . && git commit -m "Update monitome to v1.0.0" && git push
```

## Troubleshooting

### Notarization stuck
- Check status: `xcrun notarytool history --apple-id EMAIL --team-id TEAM`
- Apple status: https://developer.apple.com/system-status/

### Missing icon error
- Add 1024x1024 PNG to Assets.xcassets → AppIcon → 512pt @2x slot

### Missing category error
- Target → Info → Add `Application Category` → `Utilities`

### Skip notarization (dev only)
- Distribute App → **Copy App** instead of Upload
- Users must right-click → Open to bypass Gatekeeper
