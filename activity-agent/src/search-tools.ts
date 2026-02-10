import { Type } from "@sinclair/typebox";
import type { AgentTool } from "@mariozechner/pi-agent-core";
import type { SearchIndex } from "./search-index.js";
import type { ActivityEntry } from "./types.js";

/**
 * Format a single activity layer for display
 */
function formatActivityLayer(act: { layer: string; app?: { name: string; windowTitle?: string }; browser?: any; video?: any; ide?: any; terminal?: any; communication?: any; document?: any; activity: string; summary?: string; tags?: string[] | string }, indent = "  "): string {
  const layerLabel = act.layer === "primary" ? "PRIMARY" : "OVERLAY";
  const appName = act.app?.name || "Unknown";
  const parts = [`${indent}[${layerLabel}] ${appName} — ${act.activity}`];
  if (act.browser?.url) parts.push(`${indent}  URL: ${act.browser.url}`);
  if (act.browser?.pageTitle) parts.push(`${indent}  Page: ${act.browser.pageTitle}`);
  if (act.video?.title) parts.push(`${indent}  Video: ${act.video.title}${act.video.channel ? ` by ${act.video.channel}` : ""}`);
  if (act.ide?.filePath || act.ide?.currentFile) parts.push(`${indent}  File: ${act.ide.filePath || act.ide.currentFile}`);
  if (act.ide?.projectName) parts.push(`${indent}  Project: ${act.ide.projectName}`);
  if (act.terminal?.lastCommand) parts.push(`${indent}  Command: ${act.terminal.lastCommand}`);
  if (act.communication?.recipient) parts.push(`${indent}  With: ${act.communication.recipient}`);
  if (act.communication?.channel) parts.push(`${indent}  Channel: ${act.communication.channel}`);
  if (act.summary) parts.push(`${indent}  Summary: ${act.summary.slice(0, 150)}`);
  const tags = Array.isArray(act.tags) ? act.tags.join(", ") : act.tags || "";
  if (tags) parts.push(`${indent}  Tags: ${tags}`);
  return parts.join("\n");
}

/**
 * Format entries for display to the agent, showing activity layers
 */
function formatEntriesForAgent(entries: ActivityEntry[], maxEntries = 20): string {
  if (entries.length === 0) {
    return "No entries found.";
  }

  const limited = entries.slice(0, maxEntries);
  const lines = limited.map((e, i) => {
    const header = `[${i}] ${e.date} ${e.time}\n  Screenshot: ${e.filename}`;

    // If entry has activities array, show each layer
    if (e.activities && e.activities.length > 0) {
      const activityLines = e.activities.map(act => formatActivityLayer(act));
      return `${header}\n${activityLines.join("\n")}`;
    }

    // Fallback for old flat entries
    const parts = [
      header,
      `  [PRIMARY] ${e.app?.name || e.application} — ${e.activity}`,
    ];
    if (e.browser?.url) parts.push(`    URL: ${e.browser.url}`);
    if (e.browser?.pageTitle) parts.push(`    Page: ${e.browser.pageTitle}`);
    if (e.video?.title) parts.push(`    Video: ${e.video.title}${e.video.channel ? ` by ${e.video.channel}` : ""}`);
    if (e.ide?.filePath || e.ide?.currentFile) parts.push(`    File: ${e.ide.filePath || e.ide.currentFile}`);
    if (e.ide?.projectName) parts.push(`    Project: ${e.ide.projectName}`);
    if (e.terminal?.lastCommand) parts.push(`    Command: ${e.terminal.lastCommand}`);
    if (e.summary) parts.push(`    Summary: ${e.summary.slice(0, 150)}`);
    parts.push(`    Tags: ${e.tags.join(", ")}`);
    return parts.join("\n");
  });

  let result = lines.join("\n\n");
  if (entries.length > maxEntries) {
    result += `\n\n... and ${entries.length - maxEntries} more entries`;
  }
  return result;
}

/**
 * Format activity-level search results
 */
function formatActivityResults(results: { entry: ActivityEntry; layer: string; activity: string; summary: string; tags: string; app_name: string }[], maxResults = 20): string {
  if (results.length === 0) {
    return "No activities found.";
  }

  const limited = results.slice(0, maxResults);
  const lines = limited.map((r, i) => {
    const e = r.entry;
    const layerLabel = r.layer === "primary" ? "PRIMARY" : "OVERLAY";
    const parts = [
      `[${i}] ${e.date} ${e.time}`,
      `  Screenshot: ${e.filename}`,
      `  [${layerLabel}] ${r.app_name} — ${r.activity}`,
    ];
    if (r.summary) parts.push(`  Summary: ${r.summary.slice(0, 150)}`);
    if (r.tags) parts.push(`  Tags: ${r.tags}`);
    return parts.join("\n");
  });

  let result = lines.join("\n\n");
  if (results.length > maxResults) {
    result += `\n\n... and ${results.length - maxResults} more activities`;
  }
  return result;
}

/**
 * Create search tools for the activity agent
 */
export function createSearchTools(searchIndex: SearchIndex): AgentTool[] {
  const fullTextSearchTool: AgentTool = {
    name: "search_fulltext",
    label: "Full-text Search",
    description: `Fast full-text search across all indexed activities. Use this for keyword-based searches.
Searches at the ACTIVITY level — each screenshot can have multiple activities (primary content + overlays like notifications, calls, etc.).
Returns ranked results with layer info (PRIMARY/OVERLAY). Use specific keywords from the user's query.`,
    parameters: Type.Object({
      query: Type.String({ description: "Search keywords (e.g., 'typescript sandbox', 'github PR')" }),
      limit: Type.Optional(Type.Number({ description: "Max results to return (default 30)" })),
    }),
    execute: async (_toolCallId, rawParams) => {
      const params = rawParams as { query: string; limit?: number };
      const results = searchIndex.searchActivitiesWeighted(params.query, params.limit || 30);
      return {
        content: [{ type: "text", text: formatActivityResults(results) }],
        details: { count: results.length, query: params.query },
      };
    },
  };

  const dateRangeSearchTool: AgentTool = {
    name: "search_by_date_range",
    label: "Date Range Search",
    description: `Get all activities within a date range. Use this when the user mentions time periods like "last week", "last month", "in January", etc.
Date format: YYYY-MM-DD`,
    parameters: Type.Object({
      startDate: Type.String({ description: "Start date (YYYY-MM-DD)" }),
      endDate: Type.String({ description: "End date (YYYY-MM-DD)" }),
    }),
    execute: async (_toolCallId, rawParams) => {
      const params = rawParams as { startDate: string; endDate: string };
      const results = searchIndex.getByDateRange(params.startDate, params.endDate);
      return {
        content: [{ type: "text", text: formatEntriesForAgent(results) }],
        details: { count: results.length, startDate: params.startDate, endDate: params.endDate },
      };
    },
  };

  const dateSearchTool: AgentTool = {
    name: "search_by_date",
    label: "Date Search",
    description: `Get all activities for a specific date. Use when user asks about a specific day.`,
    parameters: Type.Object({
      date: Type.String({ description: "Date (YYYY-MM-DD)" }),
    }),
    execute: async (_toolCallId, rawParams) => {
      const params = rawParams as { date: string };
      const results = searchIndex.getByDate(params.date);
      return {
        content: [{ type: "text", text: formatEntriesForAgent(results) }],
        details: { count: results.length, date: params.date },
      };
    },
  };

  const appSearchTool: AgentTool = {
    name: "search_by_app",
    label: "App Search",
    description: `Get all activities for a specific application. Use when user mentions an app name like "Chrome", "VS Code", "Terminal", etc.`,
    parameters: Type.Object({
      appName: Type.String({ description: "Application name (e.g., 'Chrome', 'VS Code', 'Slack')" }),
    }),
    execute: async (_toolCallId, rawParams) => {
      const params = rawParams as { appName: string };
      const results = searchIndex.getByApp(params.appName);
      return {
        content: [{ type: "text", text: formatEntriesForAgent(results) }],
        details: { count: results.length, app: params.appName },
      };
    },
  };

  const listAppsTool: AgentTool = {
    name: "list_apps",
    label: "List Apps",
    description: `List all applications that have been indexed. Use this to see what apps are available before searching by app.`,
    parameters: Type.Object({}),
    execute: async () => {
      const apps = searchIndex.getApps();
      return {
        content: [{ type: "text", text: apps.length > 0 ? apps.join("\n") : "No apps indexed yet." }],
        details: { count: apps.length },
      };
    },
  };

  const listDatesTool: AgentTool = {
    name: "list_dates",
    label: "List Dates",
    description: `List all dates that have indexed activities. Use this to understand what date ranges are available.`,
    parameters: Type.Object({}),
    execute: async () => {
      const dates = searchIndex.getDates();
      return {
        content: [{ type: "text", text: dates.length > 0 ? dates.join("\n") : "No dates indexed yet." }],
        details: { count: dates.length },
      };
    },
  };

  const getStatsTool: AgentTool = {
    name: "get_index_stats",
    label: "Index Stats",
    description: `Get statistics about the search index. Use this to understand how much data is indexed.`,
    parameters: Type.Object({}),
    execute: async () => {
      const stats = searchIndex.getStats();
      const text = `Indexed entries: ${stats.entries}
Unique apps: ${stats.apps}
Unique dates: ${stats.dates}
Database size: ${(stats.dbSizeBytes / 1024).toFixed(1)} KB`;
      return {
        content: [{ type: "text", text }],
        details: stats,
      };
    },
  };

  const combinedSearchTool: AgentTool = {
    name: "search_combined",
    label: "Combined Search",
    description: `Combine date filtering with keyword search. Use this when user mentions both a time period AND keywords.
Example: "last month's articles about typescript" → dateRange + keywords "typescript article"`,
    parameters: Type.Object({
      startDate: Type.Optional(Type.String({ description: "Start date (YYYY-MM-DD)" })),
      endDate: Type.Optional(Type.String({ description: "End date (YYYY-MM-DD)" })),
      keywords: Type.Optional(Type.String({ description: "Search keywords" })),
      appName: Type.Optional(Type.String({ description: "Filter by app name" })),
    }),
    execute: async (_toolCallId, rawParams) => {
      const params = rawParams as { startDate?: string; endDate?: string; keywords?: string; appName?: string };
      let results: ActivityEntry[] = [];

      // Start with date range if specified
      if (params.startDate && params.endDate) {
        results = searchIndex.getByDateRange(params.startDate, params.endDate);
      } else if (params.keywords) {
        results = searchIndex.searchWeighted(params.keywords, 100);
      }

      // Filter by app if specified
      if (params.appName && results.length > 0) {
        const appLower = params.appName.toLowerCase();
        results = results.filter((e) => (e.app?.name || e.application).toLowerCase().includes(appLower));
      }

      // If we have date results but also keywords, filter by keywords
      if (params.startDate && params.endDate && params.keywords && results.length > 0) {
        const keywordsLower = params.keywords.toLowerCase().split(/\s+/);
        results = results.filter((e) => {
          const searchText = [
            e.activity,
            e.summary,
            e.browser?.url,
            e.browser?.pageTitle,
            e.video?.title,
            e.ide?.currentFile,
            e.terminal?.lastCommand,
            e.tags?.join(" "),
          ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase();
          return keywordsLower.some((kw: string) => searchText.includes(kw));
        });
      }

      return {
        content: [{ type: "text", text: formatEntriesForAgent(results) }],
        details: {
          count: results.length,
          startDate: params.startDate,
          endDate: params.endDate,
          keywords: params.keywords,
          appName: params.appName,
        },
      };
    },
  };

  return [
    fullTextSearchTool,
    dateRangeSearchTool,
    dateSearchTool,
    appSearchTool,
    listAppsTool,
    listDatesTool,
    getStatsTool,
    combinedSearchTool,
  ];
}
