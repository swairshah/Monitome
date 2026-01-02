# Monitome

A minimal macOS screen recording app that captures periodic screenshots for analysis.

- Periodic screenshot capture using ScreenCaptureKit (macOS 13+)
- Multi-display support (captures active display)
- GRDB/SQLite storage with automatic cleanup
- Menu bar icon with quick controls
- Event-triggered capture (app switch, tab change)

## Install

```bash
brew tap swairshah/tap
brew install --cask monitome
```

Or download from [Releases](https://github.com/swairshah/Monitome/releases).

## Configuration

- **Screenshot interval**: Default 10 seconds (configurable in Settings)
- **Storage limit**: Default 5 GB, auto-purges oldest screenshots
- **Storage location**: `~/Library/Application Support/Monitome/recordings/`

## Dev

### Build

1. Open `Monitome.xcodeproj` in Xcode
2. Add GRDB if missing: File → Add Package Dependencies → `https://github.com/groue/GRDB.swift.git`
3. Cmd+R to build and run

### Archive & Release

```bash
# In Xcode: Product → Archive → Distribute App → Direct Distribution → Export

# Create DMG
mkdir -p dist && cp -r /path/to/Monitome.app dist/
hdiutil create -volname "Monitome" -srcfolder dist -ov -format UDZO Monitome-1.0.0.dmg

# Release
gh release create v1.0.0 Monitome-1.0.0.dmg
```

### Project Structure

```
Monitome/
├── App/                  # Entry point, app delegate, state
├── Recording/            # ScreenCaptureKit, storage, display tracking
├── Views/                # SwiftUI views
├── System/               # Menu bar controller
├── Analysis/             # Analysis service client
└── service/              # Python BAML analysis service
```
