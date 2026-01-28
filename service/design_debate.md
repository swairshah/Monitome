# Design Debate: Swift + Python/BAML Integration

## Context

Monitome is a macOS app that captures periodic screenshots. We want to analyze these screenshots using an LLM (Gemini) to extract activity information, then summarize multiple extractions.

We chose BAML for prompt management because it provides:
- Type-safe structured outputs
- Easy provider switching (Gemini → OpenAI → Claude with one line change)
- Prompt testing/versioning separate from app releases

BAML has native support for Python/TypeScript but not Swift.

---

## Option 1: Call LLM Directly from Swift

**Approach:** Skip BAML, call Gemini API directly using JSON mode.

```swift
// Gemini API supports responseType: "application/json"
// Define schema, get structured JSON back
```

**Pros:**
- Simplest architecture (one process)
- No Python dependency
- Native Swift code

**Cons:**
- Tied to one provider (Gemini)
- Switching providers requires code changes
- No BAML prompt testing/versioning
- Must reimplement structured output parsing per provider

**Verdict:** Too inflexible. Provider lock-in is undesirable.

---

## Option 2: BAML REST Server

**Approach:** Run `baml dev` server, call from Swift via HTTP.

```
Swift App → HTTP → BAML dev server (localhost:2024) → Gemini
```

**Pros:**
- Official BAML approach for unsupported languages
- Auto-generates OpenAPI schema

**Cons:**
- `baml dev` is meant for development, not production
- Extra process to manage
- Unclear production deployment story

**Verdict:** Designed for development, not production use.

---

## Option 3: Python FastAPI + BAML (Chosen)

**Approach:** Custom FastAPI service using BAML's Python client.

```
Swift App → HTTP → Python FastAPI (localhost:8420) → BAML → Gemini
```

**Pros:**
- BAML works natively in Python
- Full control over the service
- Can add caching, batching, queuing
- Provider switching via BAML config
- Clean separation of concerns
- Common microservice/sidecar pattern

**Cons:**
- Two processes to manage
- Python dependency

**Verdict:** Chosen approach. Best balance of flexibility and control.

---

## Process Management Options

### A. Swift App Spawns Python Process

```swift
Process.launchedProcess(launchPath: "/usr/bin/env",
    arguments: ["uv", "run", "uvicorn", "main:app", "--port", "8420"])
```

**Pros:**
- App is self-contained
- Process lifecycle tied to app

**Cons:**
- Need to handle crash detection and restart
- Need to bundle Python/uv or expect it installed

### B. LaunchAgent (macOS)

```xml
<!-- ~/Library/LaunchAgents/com.monitome.analysis.plist -->
<key>KeepAlive</key>
<true/>  <!-- Auto-restart on crash -->
<key>RunAtLoad</key>
<true/>  <!-- Start on login -->
```

**Pros:**
- OS handles crash recovery automatically
- Service runs independently of app
- Native macOS pattern for daemons

**Cons:**
- User controls via `launchctl` (not user-friendly)
- App needs to check service health separately
- More moving parts

### C. Hybrid (LaunchAgent + App UI)

LaunchAgent manages the process, Swift app provides:
- Health status in menu bar
- "Restart Service" button
- Log viewing

**Verdict:** For now, we'll use approach A (app spawns process) with simple restart-on-crash logic. Can migrate to LaunchAgent if needed.

---

## Distribution/Bundling Options

### How Electron Does It
- Bundles entire Chromium + Node.js runtime
- Completely self-contained (~100MB+)
- Users don't need Node.js installed

### How Tauri Does It
- Uses system WebView (not bundled)
- Backend is Rust, compiled to native binary
- Much smaller (~5-10MB)

### Options for Python Service

1. **PyInstaller / py2app**
   ```bash
   pyinstaller --onefile main.py
   ```
   Compiles Python + deps to standalone executable. Bundle in .app.

2. **Nuitka**
   Compiles Python to C, then to native binary. Better performance.

3. **Bundle uv + venv**
   ```
   Monitome.app/
   └── Contents/
       └── Resources/
           └── service/
               ├── .venv/
               └── main.py
   ```
   Include pre-built virtual environment in app bundle.

4. **Expect Python installed**
   Require user to have Python/uv. Simpler but worse UX.

**Verdict:** PyInstaller to single binary is cleanest. Matches Tauri's approach. Deferred for later.

---

## Current Architecture

```
monitome/
├── Monitome/                    # Swift macOS App
│   └── Analysis/
│       ├── AnalysisClient.swift # HTTP client for Python service
│       └── AnalysisManager.swift # Business logic
│
└── service/                     # Python Analysis Service
    ├── baml_src/
    │   ├── clients.baml         # LLM provider config
    │   ├── types.baml           # ScreenActivity, AppContext, etc.
    │   ├── functions.baml       # ExtractScreenActivity, Summarize
    │   └── generators.baml      # Python client generator
    ├── baml_client/             # Generated BAML client
    ├── main.py                  # FastAPI endpoints
    └── pyproject.toml           # Dependencies
```

## Running

```bash
# Start service
cd service
GEMINI_API_KEY=your-key uv run uvicorn main:app --port 8420

# Test
curl -X POST http://127.0.0.1:8420/analyze-file \
  -H "Content-Type: application/json" \
  -d '{"file_path": "/path/to/screenshot.png"}'
```

## Future Considerations

- [ ] PyInstaller bundling for distribution
- [ ] LaunchAgent for production deployment
- [ ] Health monitoring in Swift app UI
- [ ] Batch processing endpoint for efficiency
- [ ] Caching layer for repeated similar screenshots
