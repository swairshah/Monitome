/**
 * Monitome Search Extension for Pi
 * 
 * Registers search tools for querying the activity index.
 */

import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { join } from "path";
import { homedir } from "os";
import { SearchIndex } from "../search-index.js";
import { 
  loadLearnedRules, 
  saveLearnedRules, 
  recordRuleChange, 
  undoLastChange,
  loadRulesHistory,
  type LearnedRules 
} from "../learned-rules.js";
import type { ActivityEntry } from "../types.js";

// Data directory - can be overridden via env var
const DATA_DIR = process.env.MONITOME_DATA_DIR 
  || join(homedir(), "Library/Application Support/Monitome");

/**
 * Format entries for display
 */
function formatEntries(entries: ActivityEntry[], maxEntries = 20): string {
  if (entries.length === 0) {
    return "No entries found.";
  }

  const limited = entries.slice(0, maxEntries);
  const lines = limited.map((e, i) => {
    const parts = [
      `[${i}] ${e.date} ${e.time} - ${e.app?.name || e.application}`,
      `Screenshot: ${e.filename}`,
      `Activity: ${e.activity}`,
    ];
    if (e.browser?.url) parts.push(`URL: ${e.browser.url}`);
    if (e.browser?.pageTitle) parts.push(`Page: ${e.browser.pageTitle}`);
    if (e.video?.title) parts.push(`Video: ${e.video.title} by ${e.video.channel}`);
    if (e.ide?.filePath || e.ide?.currentFile) parts.push(`File: ${e.ide.filePath || e.ide.currentFile}`);
    if (e.ide?.projectName) parts.push(`Project: ${e.ide.projectName}`);
    if (e.terminal?.lastCommand) parts.push(`Command: ${e.terminal.lastCommand}`);
    if (e.summary) parts.push(`Summary: ${e.summary.slice(0, 150)}...`);
    parts.push(`Tags: ${e.tags.join(", ")}`);
    return parts.join("\n  ");
  });

  let result = lines.join("\n\n");
  if (entries.length > maxEntries) {
    result += `\n\n... and ${entries.length - maxEntries} more entries`;
  }
  return result;
}

/**
 * Monitome Search Extension
 */
export default async function monitomeExtension(pi: ExtensionAPI): Promise<void> {
  // Initialize search index
  const dbPath = join(DATA_DIR, "activity-index.db");
  let searchIndex: SearchIndex;
  
  try {
    searchIndex = await SearchIndex.create(dbPath);
  } catch (error) {
    console.error("Failed to initialize search index:", error);
    return;
  }

  // Load learned rules
  const rulesPath = join(DATA_DIR, "learned-rules.json");
  let rules = loadLearnedRules(rulesPath);

  // =========================================================================
  // Search Tools
  // =========================================================================

  pi.registerTool({
    name: "search_activity",
    label: "Search Activity",
    description: `Search your screenshot activity index. Searches across:
- Activity descriptions and summaries
- URLs, page titles, video titles
- File paths, project names
- Terminal commands
- Tags

Use specific keywords. Returns ranked results.`,
    parameters: Type.Object({
      query: Type.String({ description: "Search keywords (e.g., 'typescript sandbox', 'github PR')" }),
      limit: Type.Optional(Type.Number({ description: "Max results to return (default 30)" }))
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      const results = searchIndex.searchWeighted(params.query, params.limit || 30);
      return {
        content: [{ type: "text", text: formatEntries(results) }],
        details: { count: results.length, query: params.query }
      };
    }
  });

  pi.registerTool({
    name: "search_by_date",
    label: "Search by Date",
    description: `Get activities for a specific date or date range.
Use when user mentions time: "yesterday", "last week", "on January 15th"
Date format: YYYY-MM-DD`,
    parameters: Type.Object({
      startDate: Type.String({ description: "Start date (YYYY-MM-DD)" }),
      endDate: Type.Optional(Type.String({ description: "End date (YYYY-MM-DD), defaults to startDate" }))
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      const endDate = params.endDate || params.startDate;
      const results = searchIndex.getByDateRange(params.startDate, endDate);
      return {
        content: [{ type: "text", text: formatEntries(results) }],
        details: { count: results.length, startDate: params.startDate, endDate }
      };
    }
  });

  pi.registerTool({
    name: "search_by_app",
    label: "Search by App",
    description: "Get activities for a specific application (e.g., 'VS Code', 'Chrome', 'Slack')",
    parameters: Type.Object({
      appName: Type.String({ description: "Application name" }),
      limit: Type.Optional(Type.Number({ description: "Max results (default 50)" }))
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      const results = searchIndex.getByApp(params.appName).slice(0, params.limit || 50);
      return {
        content: [{ type: "text", text: formatEntries(results) }],
        details: { count: results.length, app: params.appName }
      };
    }
  });

  pi.registerTool({
    name: "search_combined",
    label: "Combined Search",
    description: "Combine date range with keyword search and optional app filter",
    parameters: Type.Object({
      query: Type.Optional(Type.String({ description: "Search keywords" })),
      startDate: Type.Optional(Type.String({ description: "Start date (YYYY-MM-DD)" })),
      endDate: Type.Optional(Type.String({ description: "End date (YYYY-MM-DD)" })),
      appName: Type.Optional(Type.String({ description: "Filter by app name" })),
      limit: Type.Optional(Type.Number({ description: "Max results (default 30)" }))
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      let results: ActivityEntry[] = [];
      
      // Start with date range if provided
      if (params.startDate) {
        const endDate = params.endDate || params.startDate;
        results = searchIndex.getByDateRange(params.startDate, endDate);
      } else if (params.query) {
        results = searchIndex.searchWeighted(params.query, 100);
      } else {
        // Get recent entries
        results = searchIndex.getByDateRange(
          new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split("T")[0],
          new Date().toISOString().split("T")[0]
        );
      }
      
      // Filter by app if provided
      if (params.appName) {
        const appLower = params.appName.toLowerCase();
        results = results.filter(e => 
          (e.app?.name || e.application).toLowerCase().includes(appLower)
        );
      }
      
      // Filter by query if we started with date range
      if (params.query && params.startDate) {
        const queryLower = params.query.toLowerCase();
        results = results.filter(e =>
          e.activity.toLowerCase().includes(queryLower) ||
          e.summary?.toLowerCase().includes(queryLower) ||
          e.tags.some(t => t.toLowerCase().includes(queryLower)) ||
          e.browser?.url?.toLowerCase().includes(queryLower) ||
          e.browser?.pageTitle?.toLowerCase().includes(queryLower)
        );
      }
      
      return {
        content: [{ type: "text", text: formatEntries(results.slice(0, params.limit || 30)) }],
        details: { count: results.length }
      };
    }
  });

  pi.registerTool({
    name: "list_apps",
    label: "List Apps",
    description: "List all indexed applications with entry counts",
    parameters: Type.Object({}),
    async execute(toolCallId, params, onUpdate, ctx) {
      const apps = searchIndex.getApps();
      const lines = apps.map(app => {
        const count = searchIndex.getByApp(app).length;
        return `${app}: ${count} entries`;
      });
      return {
        content: [{ type: "text", text: `Indexed applications:\n${lines.join("\n")}` }],
        details: { count: apps.length }
      };
    }
  });

  pi.registerTool({
    name: "get_activity_status",
    label: "Get Status",
    description: "Get activity index statistics",
    parameters: Type.Object({}),
    async execute(toolCallId, params, onUpdate, ctx) {
      const stats = searchIndex.getStats();
      const text = `Activity Index Status:
- Total entries: ${stats.entries}
- Apps tracked: ${stats.apps}
- Days of data: ${stats.dates}
- Index size: ${(stats.dbSizeBytes / 1024).toFixed(1)} KB`;
      return {
        content: [{ type: "text", text }],
        details: stats
      };
    }
  });

  // =========================================================================
  // Rules/Feedback Tools
  // =========================================================================

  pi.registerTool({
    name: "update_rules",
    label: "Update Rules",
    description: `Update indexing or search rules based on user feedback.
Use when user says things like:
- "Remember that for VS Code, always note the git branch"
- "CLI should also match 'terminal' and 'command line'"
- "Don't index system notifications"`,
    parameters: Type.Object({
      feedback: Type.String({ description: "Natural language feedback about indexing or search" })
    }),
    async execute(toolCallId, params, onUpdate, ctx) {
      // For now, just record the feedback - full LLM processing would need the agent
      recordRuleChange(rulesPath, {
        feedback: params.feedback,
        action: "add",
        category: "indexing",
        rule: params.feedback,
      });
      
      // Reload rules
      rules = loadLearnedRules(rulesPath);
      
      return {
        content: [{ type: "text", text: `Recorded feedback: "${params.feedback}"\n\nThis will be applied to future indexing.` }],
        details: { success: true }
      };
    }
  });

  pi.registerTool({
    name: "show_rules",
    label: "Show Rules",
    description: "Show current learned rules for indexing and search",
    parameters: Type.Object({}),
    async execute(toolCallId, params, onUpdate, ctx) {
      const lines: string[] = ["Current Learned Rules:", ""];

      if (rules.indexing.length > 0) {
        lines.push("INDEXING RULES:");
        rules.indexing.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
        lines.push("");
      }

      if (rules.exclude.length > 0) {
        lines.push("EXCLUDE RULES:");
        rules.exclude.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
        lines.push("");
      }

      if (rules.search.length > 0) {
        lines.push("SEARCH RULES:");
        rules.search.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
        lines.push("");
      }

      if (rules.indexing.length === 0 && rules.search.length === 0 && rules.exclude.length === 0) {
        lines.push("No learned rules yet.");
      }

      return {
        content: [{ type: "text", text: lines.join("\n") }],
        details: { rules }
      };
    }
  });

  pi.registerTool({
    name: "undo_rule",
    label: "Undo Rule Change",
    description: "Undo the last rule change",
    parameters: Type.Object({}),
    async execute(toolCallId, params, onUpdate, ctx) {
      const result = undoLastChange(rulesPath);
      if (result.success) {
        rules = loadLearnedRules(rulesPath);
      }
      return {
        content: [{ type: "text", text: result.message }],
        details: { success: result.success }
      };
    }
  });

  // =========================================================================
  // Commands
  // =========================================================================

  pi.registerCommand("status", {
    description: "Show Monitome activity index status",
    handler: async (args, ctx) => {
      const stats = searchIndex.getStats();
      ctx.ui.notify(`Monitome: ${stats.entries} entries, ${stats.apps} apps, ${stats.dates} days`);
    }
  });

  pi.registerCommand("rules", {
    description: "Show current learned rules",
    handler: async (args, ctx) => {
      const lines: string[] = [];
      if (rules.indexing.length > 0) {
        lines.push(`Indexing: ${rules.indexing.length} rules`);
      }
      if (rules.search.length > 0) {
        lines.push(`Search: ${rules.search.length} rules`);
      }
      if (rules.exclude.length > 0) {
        lines.push(`Exclude: ${rules.exclude.length} rules`);
      }
      ctx.ui.notify(lines.length > 0 ? lines.join(", ") : "No rules configured");
    }
  });

  // =========================================================================
  // Session Events
  // =========================================================================

  pi.on("session_start", async (event, ctx) => {
    const stats = searchIndex.getStats();
    ctx.ui.setStatus("monitome", `${stats.entries} activities`);
  });

  // Log when extension loads
  console.error(`[monitome] Extension loaded. Index: ${searchIndex.getStats().entries} entries`);
}
