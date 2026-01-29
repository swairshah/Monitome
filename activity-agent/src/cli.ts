#!/usr/bin/env node

import { resolve, join } from "path";
import { homedir } from "os";
import { existsSync, readFileSync } from "fs";
import { ActivityAgent } from "./activity-agent.js";
import { listScreenshots, getScreenshotsAfter } from "./screenshot-parser.js";
import type { ActivityEntry } from "./types.js";

// Load environment variables from ~/.env if it exists
function loadEnvFile() {
  const envPaths = [
    join(homedir(), ".env"),
    join(homedir(), ".config", "monitome", ".env"),
  ];
  
  for (const envPath of envPaths) {
    if (existsSync(envPath)) {
      try {
        const content = readFileSync(envPath, "utf-8");
        for (const line of content.split("\n")) {
          const trimmed = line.trim();
          if (trimmed && !trimmed.startsWith("#")) {
            const eqIndex = trimmed.indexOf("=");
            if (eqIndex > 0) {
              const key = trimmed.slice(0, eqIndex).trim();
              let value = trimmed.slice(eqIndex + 1).trim();
              // Remove quotes if present
              if ((value.startsWith('"') && value.endsWith('"')) || 
                  (value.startsWith("'") && value.endsWith("'"))) {
                value = value.slice(1, -1);
              }
              if (!process.env[key]) {
                process.env[key] = value;
              }
            }
          }
        }
      } catch {
        // Ignore errors reading env file
      }
      break;
    }
  }
}

// Load env file before anything else
loadEnvFile();

// Default to Monitome's Application Support directory
const DEFAULT_DATA_DIR = join(homedir(), "Library/Application Support/Monitome");

function parseArgs(args: string[]): { dataDir: string; command: string; rest: string[] } {
  let dataDir = DEFAULT_DATA_DIR;
  let command = "status";
  const rest: string[] = [];

  let i = 0;
  while (i < args.length) {
    const arg = args[i];
    if (arg === "--data" || arg === "-d") {
      if (i + 1 < args.length) {
        dataDir = resolve(args[i + 1]);
        i += 2;
      } else {
        console.error("Error: --data requires a path argument");
        process.exit(1);
      }
    } else if (!command || command === "status") {
      // First non-flag argument is the command
      if (!arg.startsWith("-")) {
        command = arg;
        i++;
      } else {
        rest.push(arg);
        i++;
      }
    } else {
      rest.push(arg);
      i++;
    }
  }

  // If no command was found, it's still "status"
  if (!command) command = "status";

  return { dataDir, command, rest };
}

async function main() {
  const rawArgs = process.argv.slice(2);
  
  // Handle help early
  if (rawArgs.includes("--help") || rawArgs.includes("-h") || rawArgs[0] === "help") {
    showHelp();
    return;
  }

  const { dataDir, command, rest: args } = parseArgs(rawArgs);

  switch (command) {
    case "process": {
      // Process all new screenshots
      const limit = args[0] ? parseInt(args[0]) : undefined;
      await processScreenshots(dataDir, limit);
      break;
    }

    case "status": {
      // Show current status
      await showStatus(dataDir);
      break;
    }

    case "search": {
      // Smart agent search with tools
      const debugIndex = args.indexOf("--debug");
      const debug = debugIndex !== -1;
      const filteredArgs = args.filter((a) => a !== "--debug");
      const query = filteredArgs.join(" ");
      if (!query) {
        console.error("Usage: activity-agent search <query> [--debug]");
        process.exit(1);
      }
      await agentSearch(dataDir, query, debug);
      break;
    }

    case "fts": {
      // Fast SQLite FTS5 search (direct, no agent)
      const query = args.join(" ");
      if (!query) {
        console.error("Usage: activity-agent fts <query>");
        process.exit(1);
      }
      await fastSearch(dataDir, query);
      break;
    }

    case "find": {
      // Simple keyword search
      const query = args.join(" ");
      if (!query) {
        console.error("Usage: activity-agent find <keyword>");
        process.exit(1);
      }
      await keywordSearch(dataDir, query);
      break;
    }

    case "date": {
      // Show entries for a specific date
      const date = args[0];
      if (!date) {
        console.error("Usage: activity-agent date <YYYY-MM-DD>");
        process.exit(1);
      }
      await showDate(dataDir, date);
      break;
    }

    case "feedback": {
      // Process natural language feedback
      const feedback = args.join(" ");
      if (!feedback) {
        console.error("Usage: activity-agent feedback <natural language feedback>");
        console.error('Example: activity-agent feedback "when I search for java blog it should find articles about Java CLI"');
        process.exit(1);
      }
      await processFeedback(dataDir, feedback);
      break;
    }

    case "rules": {
      // Show current learned rules
      await showRules(dataDir);
      break;
    }

    case "history": {
      // Show rules change history
      await showHistory(dataDir);
      break;
    }

    case "undo": {
      // Undo last rule change
      await undoLastRuleChange(dataDir);
      break;
    }

    case "sync": {
      // Sync JSON context to SQLite index
      await syncIndex(dataDir);
      break;
    }

    case "rebuild": {
      // Rebuild SQLite index from scratch
      await rebuildIndex(dataDir);
      break;
    }

    case "apps": {
      // List all apps
      await listApps(dataDir);
      break;
    }

    case "chat": {
      // Chat message with optional history
      // Usage: activity-agent chat <message> [--history '<json>']
      const historyIndex = args.indexOf("--history");
      let historyJson: string | undefined;
      let messageArgs = args;
      
      if (historyIndex !== -1 && args[historyIndex + 1]) {
        historyJson = args[historyIndex + 1];
        messageArgs = [...args.slice(0, historyIndex), ...args.slice(historyIndex + 2)];
      }
      
      const message = messageArgs.join(" ");
      if (!message) {
        console.error("Usage: activity-agent chat <message> [--history '<json>']");
        process.exit(1);
      }
      await chatMessage(dataDir, message, historyJson);
      break;
    }

    case "help":
    default: {
      showHelp();
      break;
    }
  }
}

function showHelp() {
  console.log(`
Activity Agent - Screenshot activity tracker

Usage: activity-agent [--data <path>] <command> [options]

Global Options:
  --data, -d <path>   Data directory (default: ~/Library/Application Support/Monitome)

Commands:
  chat <message>      Conversational interface - ask anything naturally
  process [limit]     Process new screenshots (optionally limit count)
  status              Show current processing status
  search <query>      Smart search - agent uses tools to find activities
                      Use --debug to see tool calls
  fts <query>         Fast full-text search using SQLite FTS5 (no agent)
  find <keyword>      Simple keyword search - exact text matching
  date <YYYY-MM-DD>   Show entries for a specific date
  apps                List all indexed applications
  feedback <text>     Provide natural language feedback to improve indexing/search
  rules               Show current learned rules
  history             Show history of rule changes
  undo                Undo the last rule change
  sync                Sync JSON context to SQLite search index
  rebuild             Rebuild SQLite search index from scratch
  help                Show this help

Examples:
  activity-agent chat "what was I working on yesterday?"
  activity-agent chat "remember that for VS Code, always note the git branch"
  activity-agent chat "show me the rules"
  activity-agent --data ~/screenshots status
  activity-agent search "what was I doing yesterday" --debug

Environment:
  ANTHROPIC_API_KEY   Required for the AI model
`);
}

function formatEntry(entry: ActivityEntry, verbose = false): string {
  const lines: string[] = [];
  const appName = entry.app?.name || entry.application;

  lines.push(`[${entry.date} ${entry.time}] ${appName}${entry.isContinuation ? " (continuation)" : ""}`);
  lines.push(`  File: ${entry.filename}`);
  lines.push(`  Activity: ${entry.activity}`);

  if (entry.app?.windowTitle) {
    lines.push(`  Window: ${entry.app.windowTitle}`);
  }

  if (entry.app?.bundleOrPath) {
    lines.push(`  Path: ${entry.app.bundleOrPath}`);
  }

  // Browser details
  if (entry.browser) {
    if (entry.browser.url) lines.push(`  URL: ${entry.browser.url}`);
    if (entry.browser.pageTitle) lines.push(`  Page: ${entry.browser.pageTitle}`);
    if (entry.browser.pageType && entry.browser.pageType !== "other") {
      lines.push(`  Type: ${entry.browser.pageType}`);
    }
  }

  // Video details
  if (entry.video) {
    lines.push(`  Video: "${entry.video.title || "Unknown"}"`);
    if (entry.video.channel) lines.push(`  Channel: ${entry.video.channel}`);
    if (entry.video.duration) {
      const position = entry.video.position ? `${entry.video.position} / ` : "";
      lines.push(`  Duration: ${position}${entry.video.duration}`);
    }
    if (entry.video.state) lines.push(`  State: ${entry.video.state}`);
  }

  // IDE details
  if (entry.ide) {
    if (entry.ide.currentFile) {
      const path = entry.ide.filePath || entry.ide.currentFile;
      lines.push(`  File: ${path}`);
    }
    if (entry.ide.language) lines.push(`  Language: ${entry.ide.language}`);
    if (entry.ide.projectName) lines.push(`  Project: ${entry.ide.projectName}`);
    if (entry.ide.gitBranch) lines.push(`  Branch: ${entry.ide.gitBranch}`);
  }

  // Terminal details
  if (entry.terminal) {
    if (entry.terminal.cwd) lines.push(`  CWD: ${entry.terminal.cwd}`);
    if (entry.terminal.lastCommand) lines.push(`  Command: ${entry.terminal.lastCommand}`);
    if (entry.terminal.sshHost) lines.push(`  SSH: ${entry.terminal.sshHost}`);
  }

  // Communication details
  if (entry.communication) {
    if (entry.communication.channel) lines.push(`  Channel: ${entry.communication.channel}`);
    if (entry.communication.recipient) lines.push(`  With: ${entry.communication.recipient}`);
  }

  // Document details
  if (entry.document) {
    if (entry.document.documentTitle) lines.push(`  Document: ${entry.document.documentTitle}`);
    if (entry.document.documentType) lines.push(`  Type: ${entry.document.documentType}`);
  }

  // Summary (always show if available)
  if (entry.summary) {
    lines.push(`  Summary: ${entry.summary}`);
  }

  if (verbose && entry.details && entry.details !== entry.activity) {
    lines.push(`  Details: ${entry.details}`);
  }

  lines.push(`  Tags: ${entry.tags.join(", ")}`);

  return lines.join("\n");
}

async function processScreenshots(dataDir: string, limit?: number) {
  console.log(`Processing screenshots from: ${dataDir}`);

  const agent = await ActivityAgent.create({ dataDir });
  const lastTimestamp = agent.getLastProcessedTimestamp();

  let screenshots = getScreenshotsAfter(dataDir, lastTimestamp);

  if (limit && limit > 0) {
    screenshots = screenshots.slice(0, limit);
  }

  if (screenshots.length === 0) {
    console.log("No new screenshots to process.");
    return;
  }

  console.log(`Found ${screenshots.length} new screenshots to process.`);

  let processed = 0;
  let skipped = 0;

  for (let i = 0; i < screenshots.length; i++) {
    const screenshot = screenshots[i];
    console.log(`\n[${i + 1}/${screenshots.length}] Processing: ${screenshot.filename}`);

    try {
      const entry = await agent.processScreenshot(screenshot);
      if (entry === null) {
        console.log(`  ⏭ Skipped (similar to recent screenshot)`);
        skipped++;
      } else {
        console.log(formatEntry(entry));
        processed++;
      }
    } catch (error) {
      console.error(`  Error: ${error}`);
    }
  }

  console.log("\nDone processing.");
  console.log(`  Processed: ${processed}, Skipped (duplicates): ${skipped}`);

  // Show summary
  const context = agent.getContext();
  console.log(`\nTotal entries: ${context.entries.length}`);
  if (context.recentSummary) {
    console.log(`\nRecent summary: ${context.recentSummary}`);
  }
}

async function showStatus(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });
  const context = agent.getContext();

  const allScreenshots = listScreenshots(dataDir);
  const lastTimestamp = agent.getLastProcessedTimestamp();
  const pending = lastTimestamp
    ? allScreenshots.filter((s) => s.timestamp > lastTimestamp).length
    : allScreenshots.length;

  console.log(`Activity Agent Status`);
  console.log(`====================`);
  console.log(`Data directory: ${dataDir}`);
  console.log(`Total screenshots: ${allScreenshots.length}`);
  console.log(`Processed entries: ${context.entries.length}`);
  console.log(`Pending: ${pending}`);

  if (context.lastProcessed) {
    console.log(`Last processed: ${context.lastProcessed}`);
  }

  // Show search index stats
  const stats = agent.getSearchIndexStats();
  if (stats) {
    console.log(`\nSearch Index:`);
    console.log(`  Indexed: ${stats.entries} entries`);
    console.log(`  Apps: ${stats.apps}`);
    console.log(`  Dates: ${stats.dates}`);
    console.log(`  DB size: ${(stats.dbSizeBytes / 1024).toFixed(1)} KB`);
  }

  // Show phash stats
  const phashStats = agent.getPhashStats();
  console.log(`\nDuplicate Detection (pHash):`);
  console.log(`  Hashes: ${phashStats.totalHashes}`);
  console.log(`  Index size: ${(phashStats.indexSizeBytes / 1024).toFixed(1)} KB`);

  if (context.recentSummary) {
    console.log(`\nRecent summary:`);
    console.log(context.recentSummary);
  }

  // Show last 5 entries
  const recent = context.entries.slice(-5);
  if (recent.length > 0) {
    console.log(`\nLast ${recent.length} entries:`);
    for (const entry of recent) {
      console.log(formatEntry(entry));
      console.log();
    }
  }
}

async function agentSearch(dataDir: string, query: string, debug = false) {
  const agent = await ActivityAgent.create({ dataDir });

  console.log(`Searching for: "${query}"${debug ? " (debug mode)" : ""}\n`);

  const result = await agent.agentSearch(query, (event) => {
    if (debug) {
      if (event.type === "tool_start") {
        console.log(`\n┌─ Tool: ${event.content}`);
      } else if (event.type === "tool_args") {
        console.log(`│  Args: ${event.content}`);
      } else if (event.type === "tool_result") {
        const lines = (event.content || "").split("\n").slice(0, 10);
        console.log(`│  Result (${event.resultCount} entries):`);
        for (const line of lines) {
          console.log(`│    ${line}`);
        }
        if ((event.content || "").split("\n").length > 10) {
          console.log(`│    ...`);
        }
        console.log(`└─ Done`);
      } else if (event.type === "thinking") {
        console.log(`\n💭 ${event.content}`);
      }
    } else {
      if (event.type === "tool_start") {
        process.stdout.write(`[${event.content}] `);
      } else if (event.type === "tool_result") {
        process.stdout.write("✓ ");
      }
    }
  });

  console.log("\n");
  console.log(result.answer);
}

async function fastSearch(dataDir: string, query: string) {
  const agent = await ActivityAgent.create({ dataDir });

  const startTime = Date.now();
  const results = agent.searchFast(query);
  const elapsed = Date.now() - startTime;

  if (results.length === 0) {
    console.log(`No results found for: "${query}"`);
    return;
  }

  console.log(`Found ${results.length} results for: "${query}" (${elapsed}ms)\n`);

  for (const entry of results) {
    console.log(formatEntry(entry, true));
    console.log();
  }
}

async function keywordSearch(dataDir: string, query: string) {
  const agent = await ActivityAgent.create({ dataDir });
  const results = agent.search(query);

  if (results.length === 0) {
    console.log(`No results found for: "${query}"`);
    return;
  }

  console.log(`Found ${results.length} results for: "${query}"\n`);

  for (const entry of results) {
    console.log(formatEntry(entry, true));
    console.log();
  }
}

async function showDate(dataDir: string, date: string) {
  const agent = await ActivityAgent.create({ dataDir });
  const entries = agent.getEntriesForDate(date);

  if (entries.length === 0) {
    console.log(`No entries found for: ${date}`);
    return;
  }

  console.log(`Activity for ${date} (${entries.length} entries)`);
  console.log("=".repeat(50));

  let currentApp = "";
  for (const entry of entries) {
    const appName = entry.app?.name || entry.application;
    if (appName !== currentApp) {
      currentApp = appName;
      console.log(`\n## ${currentApp}`);
    }

    console.log(formatEntry(entry));
    console.log();
  }
}

async function processFeedback(dataDir: string, feedback: string) {
  const agent = await ActivityAgent.create({ dataDir });

  console.log(`Processing feedback: "${feedback}"\n`);

  const result = await agent.processFeedback(feedback);

  if (result.success) {
    console.log("✓ " + result.message);
    if (result.rulesChanged) {
      console.log("\nUpdated rules saved. Future indexing will use these rules.");
    }
  } else {
    console.error("✗ " + result.message);
  }
}

async function showRules(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });
  console.log(agent.showRules());
}

async function showHistory(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });
  console.log(agent.showHistory());
}

async function undoLastRuleChange(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });
  const result = agent.undoLastChange();

  if (result.success) {
    console.log("✓ " + result.message);
  } else {
    console.error("✗ " + result.message);
  }
}

async function syncIndex(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });

  console.log("Syncing JSON context to SQLite search index...");
  const result = agent.syncToSearchIndex();

  console.log(`✓ Synced ${result.synced} new entries, skipped ${result.skipped} existing`);

  const stats = agent.getSearchIndexStats();
  if (stats) {
    console.log(`\nSearch index stats:`);
    console.log(`  Entries: ${stats.entries}`);
    console.log(`  Apps: ${stats.apps}`);
    console.log(`  Dates: ${stats.dates}`);
    console.log(`  DB size: ${(stats.dbSizeBytes / 1024).toFixed(1)} KB`);
  }
}

async function rebuildIndex(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });

  console.log("Rebuilding SQLite search index from scratch...");
  const count = agent.rebuildSearchIndex();

  console.log(`✓ Rebuilt index with ${count} entries`);

  const stats = agent.getSearchIndexStats();
  if (stats) {
    console.log(`\nSearch index stats:`);
    console.log(`  Entries: ${stats.entries}`);
    console.log(`  Apps: ${stats.apps}`);
    console.log(`  Dates: ${stats.dates}`);
    console.log(`  DB size: ${(stats.dbSizeBytes / 1024).toFixed(1)} KB`);
  }
}

async function listApps(dataDir: string) {
  const agent = await ActivityAgent.create({ dataDir });
  const apps = agent.getApps();

  if (apps.length === 0) {
    console.log("No apps indexed yet.");
    return;
  }

  console.log(`Indexed applications (${apps.length}):\n`);
  for (const app of apps) {
    const entries = agent.getEntriesByApp(app);
    console.log(`  ${app} (${entries.length} entries)`);
  }
}

async function chatMessage(dataDir: string, message: string, historyJson?: string) {
  const agent = await ActivityAgent.create({ dataDir });
  
  // Parse history if provided
  let history: Array<{ role: "user" | "assistant"; content: string }> = [];
  if (historyJson) {
    try {
      history = JSON.parse(historyJson);
    } catch {
      // Ignore invalid JSON
    }
  }
  
  const response = await agent.chat(message, history, (event) => {
    if (event.type === "tool_start") {
      process.stdout.write(`[${event.content}] `);
    } else if (event.type === "tool_end") {
      process.stdout.write("✓ ");
    }
  });
  
  console.log("\n" + response);
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
