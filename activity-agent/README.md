# Activity Agent

An AI-powered activity tracking agent that analyzes screenshots to maintain a searchable index of your computer usage. Part of the [Monitome](https://github.com/user/Monitome) macOS application.

## Integration with Monitome

This agent is designed to work with the Monitome macOS app:

```
~/Library/Application Support/Monitome/
├── recordings/              # Screenshots captured by Swift app
├── monitome.sqlite          # Swift app's metadata DB
├── activity-context.json    # Agent's processed entries
├── activity-index.db        # Agent's FTS5 search index
├── learned-rules.json       # Agent's learned rules
└── rules-history.json       # Rule change history
```

**How it works:**
1. **Swift app** captures screenshots → saves to `recordings/`
2. **Activity Agent** processes screenshots → extracts metadata with LLM
3. **Swift app** queries the agent for search → displays results in UI

The Swift app can:
- Call the agent CLI to process new screenshots
- Query the SQLite FTS5 index directly for fast search
- Use agent search for complex natural language queries
- Provide an in-app chat interface for "agentic search"

## Overview

Activity Agent processes screenshots with timestamps (format: `YYYYMMDD_HHMMSSmmm.jpg`) and uses an LLM to:

1. Identify the active application (browser, IDE, terminal, etc.)
2. Extract URLs, file paths, video titles, and other metadata
3. Generate searchable summaries and tags
4. Track activity continuations vs. context switches
5. Learn from user feedback to improve over time

## Installation

```bash
npm install
```

## CLI Usage

### Global Options

```bash
# Specify data directory (default: ./data)
activity-agent --data ~/Library/Application\ Support/Monitome search "github repos"
activity-agent -d /path/to/data status
```

### Process Screenshots

```bash
# Process all new screenshots
activity-agent process

# Process limited number
activity-agent process 10
```

### Search

```bash
# Smart agent search (understands natural language, uses tools)
activity-agent search "what was I doing yesterday"
activity-agent search "that github repo about AI agents" --debug

# Fast FTS5 search (direct SQLite, no LLM)
activity-agent fts "typescript sandbox"

# Simple keyword search
activity-agent find "github"
```

### Other Commands

```bash
activity-agent status              # Show processing status
activity-agent date 2026-01-02     # Show entries for a date
activity-agent apps                # List indexed applications
activity-agent rules               # Show learned rules
activity-agent sync                # Sync JSON to SQLite
activity-agent rebuild             # Rebuild search index
```

### Teach the Agent

```bash
# Add indexing rules
activity-agent feedback "for Obsidian, always extract vault name and [[wiki links]]"

# Add search synonyms  
activity-agent feedback "when searching for 'CLI' also match 'terminal'"

# Add exclusions
activity-agent feedback "don't index terminal command output"

# Undo last change
activity-agent undo
```

See [docs/learned-rules.md](docs/learned-rules.md) for details.

### User Profile

The agent maintains a user profile (`user-profile.md`) that automatically tracks your interests, technologies, work patterns, and projects based on your activity.

**Automatic Updates**: The profile is automatically updated every 100 screenshots processed. No cron job needed!

```bash
# View current profile
activity-agent profile

# Manual update (based on last hour of activity)
activity-agent profile-update

# Update based on last 24 hours
activity-agent profile-update --hours 24

# Update based on a date range (e.g., last month)
activity-agent profile-update --range 2026-01-01 2026-01-31

# View profile update history
activity-agent profile-history

# Restore to a previous version (0 = most recent change)
activity-agent profile-restore 0
```

The profile includes sections for:
- **Interests** - Topics and subjects you engage with
- **Technologies & Tools** - Languages, frameworks, apps you use frequently
- **Work Patterns** - When and how you work
- **Frequently Visited** - Websites and resources you return to
- **Projects** - Current and past projects

Profile updates are stored in `profile-history.json` so you can always restore to a previous version.

To change the auto-update interval (or disable it), use the `profileUpdateInterval` option when creating the agent programmatically:
```typescript
const agent = await ActivityAgent.create({
  dataDir: "~/Library/Application Support/Monitome",
  profileUpdateInterval: 50,  // Update every 50 screenshots (default: 100, 0 to disable)
});
```

## Programmatic Usage

### From Swift (via CLI)

```swift
// Process new screenshots
let process = Process()
process.executableURL = URL(fileURLWithPath: "/path/to/activity-agent")
process.arguments = ["--data", dataDir, "process"]
try process.run()

// Agent search (returns markdown)
process.arguments = ["--data", dataDir, "search", query]

// Fast FTS search (for autocomplete, instant results)
process.arguments = ["--data", dataDir, "fts", query]
```

### From Swift (direct SQLite)

For maximum performance, query the FTS5 index directly:

```swift
import SQLite3

let db = try Connection("\(dataDir)/activity-index.db")
let results = try db.prepare("""
    SELECT raw_json FROM entries_fts 
    WHERE entries_fts MATCH ? 
    ORDER BY bm25(entries_fts) 
    LIMIT 20
""").bind(query)
```

### From TypeScript

```typescript
import { ActivityAgent } from "@swairshah/activity-agent";

const agent = await ActivityAgent.create({
  dataDir: "~/Library/Application Support/Monitome",
});

// Process screenshots
const entry = await agent.processScreenshot({
  filename: "20260102_171815225.jpg",
  timestamp: 1735858695225,
  date: "2026-01-02",
  time: "17:18:15",
  imagePath: "/path/to/screenshot.jpg",
});

// Agent search with tools
const result = await agent.agentSearch("github repos about AI", (event) => {
  if (event.type === "tool_start") console.log(`Using: ${event.content}`);
});
console.log(result.answer);

// Direct FTS search
const entries = agent.search("typescript");

// Provide feedback
await agent.processFeedback("for YouTube, always extract video duration");
```

## Data Format

### Screenshots

Screenshots must be named: `YYYYMMDD_HHMMSSmmm.jpg`

Example: `20260102_171815225.jpg` = January 2, 2026 at 17:18:15.225

### Activity Entry

```typescript
interface ActivityEntry {
  filename: string;
  timestamp: number;
  date: string;       // "2026-01-02"
  time: string;       // "17:18:15"
  
  app: {
    name: string;
    windowTitle?: string;
    category: "browser" | "ide" | "terminal" | "media" | "communication" | "productivity" | "other";
  };
  
  // Context-specific (only relevant ones populated)
  browser?: { url, domain, pageTitle, pageType };
  video?: { platform, title, channel };
  ide?: { ide, currentFile, language, projectName, gitBranch };
  terminal?: { cwd, lastCommand };
  communication?: { app, channel, recipient };
  document?: { app, documentTitle };
  
  activity: string;        // Brief description
  summary: string;         // Detailed searchable content
  tags: string[];          // Keywords
  isContinuation: boolean; // Same task as previous?
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Monitome Swift App                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ Screenshot  │  │   Search    │  │  Chat Interface │  │
│  │  Capture    │  │     UI      │  │ (Agent Search)  │  │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │
└─────────┼────────────────┼──────────────────┼───────────┘
          │                │                  │
          ▼                ▼                  ▼
┌─────────────────────────────────────────────────────────┐
│              ~/Library/Application Support/Monitome      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ recordings/  │  │ activity-   │  │ learned-      │  │
│  │  *.jpg       │  │ index.db    │  │ rules.json    │  │
│  └──────┬───────┘  └──────▲──────┘  └───────▲───────┘  │
└─────────┼─────────────────┼─────────────────┼───────────┘
          │                 │                 │
          ▼                 │                 │
┌─────────────────────────────────────────────────────────┐
│                    Activity Agent                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │  Screenshot │  │   Search    │  │    Feedback     │  │
│  │  Processor  │  │   Tools     │  │    Learning     │  │
│  │    + LLM    │  │  + FTS5     │  │                 │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Environment Variables

- `ANTHROPIC_API_KEY` - Required (default model is Claude Sonnet 4)

## Documentation

- [Learned Rules System](docs/learned-rules.md)
- [TODO](TODO.md)
