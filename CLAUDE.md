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

```bash
# Quick release flow
xcodebuild -project Monitome.xcodeproj -scheme Monitome -configuration Release archive
# Then: Xcode Organizer → Distribute App → Direct Distribution → Upload → Export
# Create DMG, notarize with xcrun notarytool, staple, upload to GitHub release
```
