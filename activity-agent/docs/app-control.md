# Controlling Monitome from Pi

This document outlines approaches for giving Pi the ability to control the Monitome app at runtime (e.g., "stop recording", "start recording", "change capture interval").

## Current Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Monitome.app   │     │   Pi Binary     │     │   Extension     │
│  (Swift)        │     │   (Bun)         │     │   (TypeScript)  │
│                 │     │                 │     │                 │
│  - Recording    │     │  - Runs agent   │     │  - Search tools │
│  - Screenshots  │     │  - Loads ext    │     │  - Rules tools  │
│  - UI           │     │                 │     │  - (Control?)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        ▲                                               │
        │                                               │
        └───────────────── ??? ─────────────────────────┘
```

The challenge: Pi runs as a subprocess, and the extension runs inside Pi. How do we communicate commands back to the Swift app?

## Approach 1: File-Based Signaling (Simplest)

Extension writes commands to a JSON file, Swift app watches for changes.

**Extension side:**
```typescript
pi.registerTool({
  name: "stop_recording",
  description: "Stop Monitome from capturing screenshots",
  parameters: Type.Object({}),
  async execute() {
    const cmdPath = join(DATA_DIR, "commands.json");
    writeFileSync(cmdPath, JSON.stringify({ 
      command: "stop_recording", 
      timestamp: Date.now() 
    }));
    return { content: [{ type: "text", text: "Recording stopped." }] };
  }
});
```

**Swift side:**
```swift
// In AppDelegate or a CommandWatcher class
let commandsURL = dataDir.appendingPathComponent("commands.json")

// Watch file with DispatchSource
let fileDescriptor = open(commandsURL.path, O_EVTONLY)
let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fileDescriptor,
    eventMask: .write,
    queue: .main
)
source.setEventHandler {
    self.handleCommand()
}
source.resume()

func handleCommand() {
    guard let data = try? Data(contentsOf: commandsURL),
          let cmd = try? JSONDecoder().decode(Command.self, from: data) else { return }
    
    switch cmd.command {
    case "stop_recording":
        AppState.shared.isRecording = false
    case "start_recording":
        AppState.shared.isRecording = true
    case "set_interval":
        if let interval = cmd.value as? Int {
            UserDefaults.standard.set(interval, forKey: "captureInterval")
        }
    default:
        break
    }
}
```

**Pros:** Simple, no server needed, works immediately  
**Cons:** Polling delay (or need file watcher), no response back to Pi

## Approach 2: Local HTTP Server

Swift app runs a tiny HTTP server, extension makes requests.

**Swift side (using Vapor or raw NWListener):**
```swift
// Simple HTTP server on localhost:8421
let server = HTTPServer(port: 8421)
server.route("/stop-recording") { _ in
    AppState.shared.isRecording = false
    return HTTPResponse(status: .ok, body: "stopped")
}
server.route("/start-recording") { _ in
    AppState.shared.isRecording = true
    return HTTPResponse(status: .ok, body: "started")
}
server.route("/status") { _ in
    return HTTPResponse(status: .ok, body: JSON([
        "isRecording": AppState.shared.isRecording,
        "screenshotCount": AppState.shared.todayScreenshotCount
    ]))
}
```

**Extension side:**
```typescript
pi.registerTool({
  name: "stop_recording",
  description: "Stop Monitome from capturing screenshots",
  parameters: Type.Object({}),
  async execute() {
    const res = await fetch("http://localhost:8421/stop-recording", { method: "POST" });
    if (res.ok) {
      return { content: [{ type: "text", text: "Recording stopped." }] };
    }
    return { content: [{ type: "text", text: "Failed to stop recording." }] };
  }
});
```

**Pros:** Bidirectional, immediate, can return status  
**Cons:** Need to add HTTP server dependency, port management

## Approach 3: SQLite Command Queue

Use the existing SQLite database as a command queue.

**Schema:**
```sql
CREATE TABLE commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    command TEXT NOT NULL,
    params TEXT,  -- JSON
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME
);
```

**Extension side:**
```typescript
pi.registerTool({
  name: "stop_recording",
  description: "Stop Monitome from capturing screenshots",
  parameters: Type.Object({}),
  async execute() {
    db.prepare("INSERT INTO commands (command) VALUES (?)").run("stop_recording");
    return { content: [{ type: "text", text: "Command queued. Recording will stop shortly." }] };
  }
});
```

**Swift side:**
```swift
// Poll every second (or use SQLite update hook)
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    let commands = db.execute("SELECT * FROM commands WHERE processed_at IS NULL")
    for cmd in commands {
        switch cmd.command {
        case "stop_recording":
            AppState.shared.isRecording = false
        // ...
        }
        db.execute("UPDATE commands SET processed_at = ? WHERE id = ?", [Date(), cmd.id])
    }
}
```

**Pros:** Uses existing infrastructure, persistent history, atomic  
**Cons:** Polling latency, slightly more complex

## Approach 4: macOS Distributed Notifications

Use Apple's IPC mechanism for cross-process communication.

**Swift side:**
```swift
DistributedNotificationCenter.default().addObserver(
    self,
    selector: #selector(handleCommand(_:)),
    name: NSNotification.Name("com.monitome.command"),
    object: nil
)

@objc func handleCommand(_ notification: Notification) {
    guard let command = notification.userInfo?["command"] as? String else { return }
    switch command {
    case "stop_recording":
        AppState.shared.isRecording = false
    // ...
    }
}
```

**Extension side (needs native helper or file trigger):**
```typescript
// Can't directly post distributed notifications from Node/Bun
// Would need a small Swift CLI helper:
// $ monitome-ctl stop-recording

import { execSync } from "child_process";

pi.registerTool({
  name: "stop_recording",
  async execute() {
    execSync("monitome-ctl stop-recording");
    return { content: [{ type: "text", text: "Recording stopped." }] };
  }
});
```

**Pros:** Native macOS IPC, no polling  
**Cons:** Needs additional native helper binary

## Recommendation

For Monitome, **Approach 1 (File-Based)** or **Approach 3 (SQLite)** are the best starting points:

1. **File-based** is simplest to implement and test
2. **SQLite** integrates with existing infrastructure and provides command history

If bidirectional communication becomes important (e.g., Pi needs to know current recording status before deciding), upgrade to **Approach 2 (HTTP Server)**.

## Potential Control Tools

```typescript
// Recording control
pi.registerTool({ name: "start_recording", ... });
pi.registerTool({ name: "stop_recording", ... });
pi.registerTool({ name: "pause_recording", ... });  // Temporary pause

// Settings
pi.registerTool({ name: "set_capture_interval", ... });  // e.g., 30s, 60s, 120s
pi.registerTool({ name: "set_storage_limit", ... });     // e.g., 5GB, 10GB

// Status (read-only, could query directly)
pi.registerTool({ name: "get_recording_status", ... });
pi.registerTool({ name: "get_storage_usage", ... });

// Advanced
pi.registerTool({ name: "capture_now", ... });           // Force immediate capture
pi.registerTool({ name: "exclude_current_app", ... });   // Add current app to exclusion list
```

## Security Considerations

- Commands should only be accepted from the local Pi process
- File-based: Use restrictive file permissions (700)
- HTTP: Bind to localhost only, consider a shared secret
- Validate all command parameters before execution
