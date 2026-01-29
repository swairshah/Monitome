# Pi Agent Integration Plan

## Goal
Replace the custom activity-agent with Pi (the full pi-coding-agent) to get:
- Richer agent experience (session management, branching, compaction)
- Less maintenance (leverage Pi's infrastructure)
- Extensibility via Pi's extension system

## Architecture

```
Monitome.app/
├── Contents/MacOS/
│   ├── Monitome              (Swift app)
│   ├── pi                    (Pi binary - compiled from pi-coding-agent)
│   └── monitome-indexer      (Screenshot indexer - separate from search)
├── Contents/Resources/
│   └── extensions/
│       └── monitome-search/
│           └── index.js      (Pi extension with search tools)
```

## Components

### 1. Pi Binary
- Compile pi-coding-agent with bun: `bun build src/cli.ts --compile --outfile pi`
- ~79MB binary (vs 60MB for current activity-agent)
- Ships with full Pi features: sessions, compaction, tools, extensions

### 2. Monitome Search Extension
Pi extension that registers:
- **Tools**: `search_activity`, `search_by_date`, `search_by_app`, `update_rules`, `show_rules`, `undo_rule`
- **Commands**: `/search`, `/status`, `/rules`
- **Session hooks**: Show index stats on session start

### 3. Monitome Indexer
Separate lightweight binary for periodic screenshot indexing:
- Runs every 60s via Swift app
- Uses LLM to analyze screenshots
- Writes to SQLite index + phash index
- No Pi dependency (keep simple)

### 4. Swift App Changes
- Replace `ActivityAgentManager` calls from `activity-agent` to `pi`
- Use `--session-dir` pointing to Monitome's data dir
- Use `--continue` to resume sessions
- Load extension via `--extension`

## Session Management

### Session Directory
```
~/Library/Application Support/Monitome/
├── sessions/                    # Pi session files
│   └── monitome/
│       └── 2026-01-28T...jsonl  # Session files
├── activity-index.db            # SQLite FTS index
├── phash-index.json             # Duplicate detection
└── learned-rules.json           # User feedback rules
```

### How Sessions Work
1. Swift app launches Pi with `--session-dir .../Monitome/sessions/monitome`
2. Pi creates/resumes session files automatically
3. Full conversation history persisted in JSONL
4. Compaction happens automatically when context gets long
5. User can branch/navigate via Pi's built-in commands

## Extension Implementation

```typescript
// extensions/monitome-search/index.ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { SearchIndex } from "./search-index";
import { LearnedRulesManager } from "./learned-rules";

export default async function monitomeExtension(pi: ExtensionAPI) {
  const dataDir = process.env.MONITOME_DATA_DIR 
    || `${process.env.HOME}/Library/Application Support/Monitome`;
  
  const searchIndex = await SearchIndex.create(`${dataDir}/activity-index.db`);
  const rules = new LearnedRulesManager(`${dataDir}/learned-rules.json`);

  // Register search tool
  pi.registerTool({
    name: "search_activity",
    label: "Search Activity",
    description: "Search your screenshot activity index for past activities",
    parameters: Type.Object({
      query: Type.String({ description: "Search query" }),
      limit: Type.Optional(Type.Number({ description: "Max results (default 30)" }))
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      const results = searchIndex.searchWeighted(params.query, params.limit || 30);
      return {
        content: [{ type: "text", text: formatResults(results) }],
        details: { count: results.length }
      };
    }
  });

  // Register date range search
  pi.registerTool({
    name: "search_by_date",
    label: "Search by Date",
    description: "Get activities for a specific date or date range",
    parameters: Type.Object({
      startDate: Type.String({ description: "Start date (YYYY-MM-DD)" }),
      endDate: Type.Optional(Type.String({ description: "End date (YYYY-MM-DD)" }))
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      const end = params.endDate || params.startDate;
      const results = searchIndex.getByDateRange(params.startDate, end);
      return {
        content: [{ type: "text", text: formatResults(results) }],
        details: { count: results.length }
      };
    }
  });

  // Register update rules tool
  pi.registerTool({
    name: "update_rules",
    label: "Update Rules",
    description: "Update indexing or search rules based on feedback",
    parameters: Type.Object({
      feedback: Type.String({ description: "Natural language feedback" })
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      const result = await rules.processFeedback(params.feedback);
      return {
        content: [{ type: "text", text: result.message }],
        details: { success: result.success }
      };
    }
  });

  // Show rules command
  pi.registerCommand("rules", {
    description: "Show current learned rules",
    handler: async (args, ctx) => {
      ctx.ui.notify(rules.showRules());
    }
  });

  // Show status on session start
  pi.on("session_start", async (event, ctx) => {
    const stats = searchIndex.getStats();
    ctx.ui.setStatus("monitome", `${stats.entries} activities indexed`);
  });
}
```

## Swift Integration

```swift
// ActivityAgentManager.swift

class ActivityAgentManager {
    private let piPath: URL
    private let extensionPath: URL
    private let sessionDir: URL
    private let dataDir: URL
    
    func chat(_ message: String) async -> String {
        let args = [
            "--session-dir", sessionDir.path,
            "--continue",
            "--extension", extensionPath.path,
            "--print",  // Non-interactive mode
            "--provider", "anthropic",
            "--model", "claude-haiku-4-5",
            message
        ]
        
        return try await runPi(args)
    }
}
```

## Build Process

```bash
# 1. Build Pi binary
cd pi-mono/packages/coding-agent
bun build src/cli.ts --compile --outfile pi

# 2. Build extension (bundle, don't compile)
cd monitome/activity-agent
bun build src/extension/index.ts --outfile dist/monitome-search.js --target node

# 3. Build indexer
bun build src/indexer/cli.ts --compile --outfile dist/monitome-indexer

# 4. Copy to app bundle
cp pi Monitome.app/Contents/MacOS/
cp dist/monitome-search.js Monitome.app/Contents/Resources/extensions/
cp dist/monitome-indexer Monitome.app/Contents/MacOS/
```

## Migration Path

1. **Phase 1**: Create extension with search tools (reuse existing search-index.ts, learned-rules.ts)
2. **Phase 2**: Update Swift app to call Pi instead of activity-agent
3. **Phase 3**: Split indexer into separate binary
4. **Phase 4**: Remove old activity-agent code
5. **Phase 5**: Update build scripts and release process

## Questions to Resolve

1. **Extension bundling**: Should extension be compiled into Pi or loaded at runtime?
   - Runtime loading is more flexible but adds complexity
   - Compiled-in is simpler but requires Pi rebuild for extension changes

2. **Indexer integration**: Keep separate or make it a Pi command?
   - Separate: Simpler, no Pi dependency for indexing
   - Pi command: Unified, but heavier

3. **Session UI**: Should Swift app show Pi's session tree, or just linear chat?
   - Linear is simpler, matches current UI
   - Tree would need custom Swift components

## Next Steps

- [ ] Create extension skeleton
- [ ] Port search tools to extension format
- [ ] Test Pi with extension locally
- [ ] Update Swift to call Pi
- [ ] Update build scripts
