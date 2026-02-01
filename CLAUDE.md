# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

### Swift App (macOS)
```bash
open Monitome.xcodeproj   # Open in Xcode
# Cmd+R to build and run
```

Requires package dependencies:
- GRDB: `https://github.com/groue/GRDB.swift.git`
- KeyboardShortcuts: `https://github.com/sindresorhus/KeyboardShortcuts`

### Python Analysis Service
```bash
cd service
GEMINI_API_KEY=your-key uv run uvicorn main:app --port 8420
```

Or directly:
```bash
cd service
GEMINI_API_KEY=your-key uv run main.py
```

### Regenerate BAML Client
```bash
cd service
baml-cli generate
```

## Architecture

This is a macOS menu bar app that captures periodic screenshots and analyzes them using an LLM.

### Swift App (`Monitome/`)
- **App/AppDelegate.swift** - Entry point, coordinates ScreenRecorder and EventTriggerMonitor
- **App/AppState.swift** - Singleton observable state (isRecording, eventTriggersEnabled, todayScreenshotCount)
- **Recording/ScreenRecorder.swift** - Uses ScreenCaptureKit to capture screenshots on interval and events
- **Recording/StorageManager.swift** - GRDB/SQLite storage, auto-purge when storage limit reached
- **Recording/EventTriggerMonitor.swift** - Captures on app switch, browser tab change (accessibility API)
- **Analysis/AnalysisClient.swift** - HTTP client for the Python service

Key patterns:
- State changes via `AppState.shared` which persists to UserDefaults and posts notifications
- Screenshot capture pauses on sleep/lock/screensaver, resumes on wake/unlock
- Multi-display support via ActiveDisplayTracker

### Python Service (`service/`)
FastAPI service using BAML for LLM prompt management.

- **main.py** - FastAPI endpoints: `/analyze-file`, `/analyze`, `/quick-extract`, `/summarize`, `/health`
- **baml_src/clients.baml** - Gemini client config (uses `GEMINI_API_KEY` env var)
- **baml_src/types.baml** - Response types: ScreenActivity, AppContext, ActivitySummary
- **baml_src/functions.baml** - LLM prompts: ExtractScreenActivity, SummarizeActivities, QuickExtract
- **baml_client/** - Auto-generated Python client from BAML

The service runs on port 8420. The Swift app communicates with it via HTTP.

## Storage

- Screenshots: `~/Library/Application Support/Monitome/recordings/`
- Database: `~/Library/Application Support/Monitome/monitome.sqlite`
- Default storage limit: 5GB, auto-purges oldest when exceeded

## Release

See DEV.md and RELEASE.md for archiving, notarization, and Homebrew cask update process.

### Apple Notarization Credentials
- **Apple ID**: swairshah@gmail.com
- **Team ID**: 8B9YURJS4G
- **App-Specific Password**: Stored in `~/.env` as `APPLE_APP_PASSWORD`

### Quick Release Flow

```bash
# 1. Build, sign, and create DMG
./scripts/build-release.sh 0.x.x

# 2. Notarize (if not done by script)
xcrun notarytool submit dist/Monitome-0.x.x.dmg \
    --apple-id "swairshah@gmail.com" \
    --team-id "8B9YURJS4G" \
    --password "$(grep APPLE_APP_PASSWORD ~/.env | cut -d= -f2)" \
    --wait

# 3. Staple the notarization ticket
xcrun stapler staple dist/Monitome-0.x.x.dmg

# 4. Create GitHub release
gh release create v0.x.x dist/Monitome-0.x.x.dmg --title "v0.x.x" --notes "Release notes"

# 5. Update Homebrew tap (required for `brew install` to get new version)
cd ~/work/projects/homebrew-tap
# Edit Casks/monitome.rb: update version and sha256
git add Casks/monitome.rb
git commit -m "Update monitome to v0.x.x"
git push
```

### Homebrew Tap Repository
- **Path**: `~/work/projects/homebrew-tap`
- **GitHub**: https://github.com/swairshah/homebrew-tap
- **Cask file**: `Casks/monitome.rb`

After each release, update the cask with the new version and SHA256 hash.
