import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import { Agent, type AgentMessage } from "@mariozechner/pi-agent-core";
import { getModel, type Model } from "@mariozechner/pi-ai";
import type {
  ActivityContext,
  ActivityEntry,
  ScreenshotInfo,
  AppMetadata,
  BrowserMetadata,
  VideoMetadata,
  IdeMetadata,
  TerminalMetadata,
  CommunicationMetadata,
  DocumentMetadata,
} from "./types.js";
import {
  loadLearnedRules,
  saveLearnedRules,
  formatIndexingRules,
  formatSearchRules,
  recordRuleChange,
  undoLastChange,
  loadRulesHistory,
  type LearnedRules,
  type RulesHistory,
  type RuleChange,
} from "./learned-rules.js";
import { SearchIndex } from "./search-index.js";
import { createSearchTools } from "./search-tools.js";
import { PhashManager } from "./phash.js";
import { UserProfileManager, type ProfileEdit, type ProfileHistory } from "./user-profile.js";
import { Type } from "@sinclair/typebox";
import type { AgentTool } from "@mariozechner/pi-agent-core";

const SYSTEM_PROMPT = `You are indexing screenshots for a personal activity search engine. Think like the person who took this screenshot - what terms would THEY use later to find this moment?

Your goal: Extract SEARCHABLE information. Focus on what makes this screenshot FINDABLE later.

Ask yourself: "If I wanted to find this screenshot in 6 months, what would I search for?"
- Topic/subject being worked on
- Names of people, projects, repos, files
- Key concepts, technologies, tools
- What was being read/watched/coded

Extract structured metadata:

1. **App** (required): name, window title, category (browser/ide/terminal/media/communication/productivity/design/system/other)

2. **Browser** (if applicable): url, domain, page title, page type (video/article/social/search/documentation/code/email/chat/shopping/other)

3. **Video** (if watching): platform, title, channel, duration

4. **IDE** (if coding): ide name, current file, project name, language, git branch

5. **Terminal** (if applicable): cwd, last command

6. **Communication** (if chatting): app, channel/recipient

7. **Document** (if applicable): app, document title

Respond with JSON (no markdown):
{
  "app": { "name": "App", "windowTitle": "Title", "category": "browser|ide|terminal|media|communication|productivity|other" },
  "browser": { "url": "full url", "domain": "domain.com", "pageTitle": "Title", "pageType": "video|article|documentation|code|other" },
  "video": { "platform": "YouTube", "title": "Full Video Title", "channel": "Channel", "duration": "12:34" },
  "ide": { "ide": "VS Code", "currentFile": "file.ts", "filePath": "/full/path", "language": "TypeScript", "projectName": "project" },
  "terminal": { "cwd": "/path", "lastCommand": "npm run build" },
  "communication": { "app": "Slack", "channel": "#channel", "recipient": "Person" },
  "document": { "app": "Notion", "documentTitle": "Title" },
  "activity": "Specific searchable description - what would you search to find this?",
  "summary": "Key searchable content: article titles, video names, code topics, project names, technologies, concepts. 1-2 sentences max.",
  "tags": ["searchable", "terms", "project-names", "technologies", "topics", "people"],
  "isContinuation": true/false
}

FOCUS ON SEARCHABILITY:
- Extract the EXACT URL, article title, video title, repo name, file path
- Tags should be search terms: project names, technologies, concepts, people
- Activity = what you'd type to find this ("reading Java CLI blog post", "debugging auth in pi-mono")
- Summary = key facts that make this findable (author names, specific topics, error messages)
- Skip generic info (window chrome, UI elements) - focus on CONTENT
- Only include relevant metadata objects

CRITICAL - SEPARATE OVERLAPPING UI LAYERS:
Screenshots often show multiple overlapping elements. You MUST distinguish between them:
- **Main content** = the primary window/app the user is focused on (usually the largest, behind everything)
- **Overlays** = notifications, FaceTime/call popups, PiP video, Spotlight, system alerts, etc.

The "app" and main metadata (browser, ide, etc.) should describe the PRIMARY content only.
Overlays should be noted in "summary" or "tags" but NEVER mixed into the main metadata.

Example: If the screenshot shows a blog post in Chrome with a FaceTime notification overlay:
- app.name = "Chrome" (the main content)
- browser.pageTitle = the article title (NOT the caller's name)
- summary = mention both: "Reading article about X on domain.com. FaceTime call from Person visible as overlay."
- tags = include both the article topic AND the person's name (both are searchable)

DO NOT conflate overlay content with main content. A notification showing "John Smith calling" does NOT mean John Smith wrote the article behind it.`;

/**
 * Analysis result from the LLM
 */
interface AnalysisResult {
  app: AppMetadata;
  browser?: BrowserMetadata;
  video?: VideoMetadata;
  ide?: IdeMetadata;
  terminal?: TerminalMetadata;
  communication?: CommunicationMetadata;
  document?: DocumentMetadata;
  activity: string;
  details: string;
  summary: string;
  tags: string[];
  isContinuation: boolean;
}

/**
 * Activity tracking agent that analyzes screenshots and maintains context
 */
export class ActivityAgent {
  private agent: Agent;
  private context: ActivityContext;
  private dataDir: string;
  private contextPath: string;
  private rulesPath: string;
  private dbPath: string;
  private rules: LearnedRules;
  private model: Model<any>;
  private searchIndex: SearchIndex | null = null;
  private searchIndexEnabled: boolean;
  private phashManager: PhashManager;
  private profileManager: UserProfileManager;
  private profileUpdateInterval: number;

  private constructor(
    options: {
      dataDir: string;
      model?: Model<any>;
      contextPath?: string;
      rulesPath?: string;
      dbPath?: string;
      enableSearchIndex?: boolean;
      /** How often to auto-update profile (in # of screenshots). Default: 100. Set to 0 to disable. */
      profileUpdateInterval?: number;
    },
    searchIndex: SearchIndex | null
  ) {
    this.dataDir = options.dataDir;
    this.contextPath = options.contextPath || join(options.dataDir, "activity-context.json");
    this.rulesPath = options.rulesPath || join(options.dataDir, "learned-rules.json");
    this.dbPath = options.dbPath || join(options.dataDir, "activity-index.db");
    this.searchIndexEnabled = options.enableSearchIndex !== false;
    this.searchIndex = searchIndex;

    // Load existing context and rules
    this.context = this.loadContext();
    this.rules = loadLearnedRules(this.rulesPath);

    // Initialize phash manager for duplicate detection
    this.phashManager = new PhashManager(this.dataDir);

    // Initialize agent with rules-enhanced prompt
    this.model = options.model || getModel("anthropic", "claude-haiku-4-5");

    // Initialize profile manager
    this.profileManager = new UserProfileManager(this.dataDir, this.model);
    this.profileUpdateInterval = options.profileUpdateInterval ?? 100;

    this.agent = new Agent({
      initialState: {
        systemPrompt: this.buildIndexingPrompt(),
        model: this.model,
        thinkingLevel: "off",
        tools: [],
        messages: [],
      },
    });
  }

  /**
   * Create an ActivityAgent (async factory)
   */
  static async create(options: {
    dataDir: string;
    model?: Model<any>;
    contextPath?: string;
    rulesPath?: string;
    dbPath?: string;
    enableSearchIndex?: boolean;
    /** How often to auto-update profile (in # of screenshots). Default: 100. Set to 0 to disable. */
    profileUpdateInterval?: number;
  }): Promise<ActivityAgent> {
    let searchIndex: SearchIndex | null = null;
    if (options.enableSearchIndex !== false) {
      const dbPath = options.dbPath || join(options.dataDir, "activity-index.db");
      searchIndex = await SearchIndex.create(dbPath);
    }
    return new ActivityAgent(options, searchIndex);
  }

  /**
   * Build the indexing prompt with learned rules
   */
  private buildIndexingPrompt(): string {
    return SYSTEM_PROMPT + formatIndexingRules(this.rules);
  }

  /**
   * Reload rules from disk and update agent prompt
   */
  reloadRules(): void {
    this.rules = loadLearnedRules(this.rulesPath);
    this.agent.setSystemPrompt(this.buildIndexingPrompt());
  }

  /**
   * Get current learned rules
   */
  getLearnedRules(): LearnedRules {
    return this.rules;
  }

  /**
   * Load context from disk
   */
  private loadContext(): ActivityContext {
    if (existsSync(this.contextPath)) {
      const data = readFileSync(this.contextPath, "utf-8");
      return JSON.parse(data);
    }
    return {
      entries: [],
      sessions: [],
      recentSummary: "",
    };
  }

  /**
   * Save context to disk
   */
  private saveContext(): void {
    const dir = dirname(this.contextPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(this.contextPath, JSON.stringify(this.context, null, 2));
  }

  /**
   * Get recent context for the prompt
   */
  private getRecentContext(): string {
    const recentEntries = this.context.entries.slice(-5);
    if (recentEntries.length === 0) {
      return "No previous activity recorded.";
    }

    const formatEntry = (e: ActivityEntry): string => {
      let line = `- [${e.time}] ${e.app?.name || e.application}: ${e.activity}`;
      if (e.isContinuation) line += " (continuation)";
      if (e.browser?.url) line += `\n    URL: ${e.browser.url}`;
      if (e.video?.title) line += `\n    Video: "${e.video.title}" by ${e.video.channel}`;
      if (e.ide?.currentFile) line += `\n    File: ${e.ide.filePath || e.ide.currentFile}`;
      if (e.terminal?.lastCommand) line += `\n    Command: ${e.terminal.lastCommand}`;
      return line;
    };

    return `Recent activity (last ${recentEntries.length} screenshots):
${recentEntries.map(formatEntry).join("\n")}

Running summary: ${this.context.recentSummary || "Starting new session."}`;
  }

  /**
   * Analyze a single screenshot
   */
  async analyzeScreenshot(screenshot: ScreenshotInfo): Promise<ActivityEntry> {
    // Load image as base64
    const imageData = readFileSync(screenshot.path);
    const base64 = imageData.toString("base64");

    // Build prompt with context
    const contextInfo = this.getRecentContext();
    const prompt = `Analyze this screenshot taken at ${screenshot.time} on ${screenshot.date}.

Previous context:
${contextInfo}

Extract all structured information from this screenshot.`;

    // Clear messages and prompt with image
    this.agent.clearMessages();

    await this.agent.prompt(prompt, [{ type: "image", data: base64, mimeType: "image/jpeg" }]);

    // Get the response
    const messages = this.agent.state.messages;
    const assistantMessage = messages.find(
      (m): m is AgentMessage & { role: "assistant" } => m.role === "assistant"
    );

    if (!assistantMessage) {
      throw new Error("No response from agent");
    }

    // Parse JSON response
    const textContent = assistantMessage.content.find(
      (c): c is { type: "text"; text: string } => c.type === "text"
    );
    if (!textContent) {
      throw new Error("No text content in response");
    }

    let analysis: AnalysisResult;

    try {
      // Remove potential markdown code block wrapper
      let jsonText = textContent.text.trim();
      if (jsonText.startsWith("```json")) {
        jsonText = jsonText.slice(7);
      }
      if (jsonText.startsWith("```")) {
        jsonText = jsonText.slice(3);
      }
      if (jsonText.endsWith("```")) {
        jsonText = jsonText.slice(0, -3);
      }
      analysis = JSON.parse(jsonText.trim());
    } catch (e) {
      console.error("Failed to parse JSON response:", textContent.text);
      throw new Error(`Failed to parse analysis: ${e}`);
    }

    // Clean up null values from nested objects
    const cleanNulls = <T>(obj: T | undefined | null): T | undefined => {
      if (!obj) return undefined;
      const cleaned: Partial<T> = {};
      for (const [key, value] of Object.entries(obj as object)) {
        if (value !== null && value !== undefined) {
          (cleaned as Record<string, unknown>)[key] = value;
        }
      }
      return Object.keys(cleaned).length > 0 ? (cleaned as T) : undefined;
    };

    const entry: ActivityEntry = {
      filename: screenshot.filename,
      timestamp: screenshot.timestamp,
      date: screenshot.date,
      time: screenshot.time,
      app: analysis.app,
      browser: cleanNulls<BrowserMetadata>(analysis.browser),
      video: cleanNulls<VideoMetadata>(analysis.video),
      ide: cleanNulls<IdeMetadata>(analysis.ide),
      terminal: cleanNulls<TerminalMetadata>(analysis.terminal),
      communication: cleanNulls<CommunicationMetadata>(analysis.communication),
      document: cleanNulls<DocumentMetadata>(analysis.document),
      activity: analysis.activity,
      details: analysis.details,
      summary: analysis.summary,
      tags: analysis.tags,
      isContinuation: analysis.isContinuation,
      // Legacy fields
      application: analysis.app.name,
      url: analysis.browser?.url,
    };

    return entry;
  }

  /**
   * Process a screenshot and add to context
   * Returns null if screenshot is a duplicate (similar to recent screenshot)
   */
  async processScreenshot(screenshot: ScreenshotInfo): Promise<ActivityEntry | null> {
    // Check for perceptual similarity to recent screenshots
    const phashResult = await this.phashManager.checkAndAdd(
      screenshot.path,
      screenshot.filename,
      screenshot.timestamp
    );

    if (phashResult.isDuplicate) {
      // Skip duplicate - just mark as processed
      this.context.lastProcessed = screenshot.filename;
      this.saveContext();
      return null;
    }

    const entry = await this.analyzeScreenshot(screenshot);

    // Add to context
    this.context.entries.push(entry);
    this.context.lastProcessed = screenshot.filename;

    // Index in SQLite
    if (this.searchIndex) {
      this.searchIndex.indexEntry(entry);
    }

    // Update recent summary every 10 entries
    if (this.context.entries.length % 10 === 0) {
      await this.updateSummary();
    }

    // Update user profile periodically
    if (this.profileUpdateInterval > 0 && this.context.entries.length % this.profileUpdateInterval === 0) {
      await this.autoUpdateProfile();
    }

    // Save context
    this.saveContext();

    return entry;
  }

  /**
   * Automatically update profile (called during processing)
   * Uses last 100 entries for the update
   */
  private async autoUpdateProfile(): Promise<void> {
    const recentEntries = this.context.entries.slice(-100);
    if (recentEntries.length === 0) return;

    try {
      await this.profileManager.updateProfile(recentEntries);
    } catch (e) {
      // Don't fail screenshot processing if profile update fails
      console.error("Auto profile update failed:", e);
    }
  }

  /**
   * Check if a screenshot is similar to recent ones without processing
   */
  async isDuplicate(screenshot: ScreenshotInfo): Promise<{ isDuplicate: boolean; similarTo?: string }> {
    const result = await this.phashManager.checkAndAdd(
      screenshot.path,
      screenshot.filename,
      screenshot.timestamp
    );
    return { isDuplicate: result.isDuplicate, similarTo: result.similarTo };
  }

  /**
   * Get phash stats
   */
  getPhashStats(): { totalHashes: number; indexSizeBytes: number } {
    return this.phashManager.getStats();
  }

  /**
   * Update the running summary
   */
  private async updateSummary(): Promise<void> {
    const recent = this.context.entries.slice(-20);
    if (recent.length === 0) return;

    this.agent.clearMessages();
    await this.agent.prompt(
      `Based on these recent activity entries, provide a brief 2-3 sentence summary of what the user has been working on:

${recent.map((e) => `- [${e.date} ${e.time}] ${e.app?.name || e.application}: ${e.activity}`).join("\n")}

Respond with just the summary text, no JSON.`
    );

    const messages = this.agent.state.messages;
    const assistantMessage = messages.find(
      (m): m is AgentMessage & { role: "assistant" } => m.role === "assistant"
    );
    if (assistantMessage) {
      const textContent = assistantMessage.content.find(
        (c): c is { type: "text"; text: string } => c.type === "text"
      );
      if (textContent) {
        this.context.recentSummary = textContent.text.trim();
        this.saveContext();
      }
    }
  }

  /**
   * Get the current context
   */
  getContext(): ActivityContext {
    return this.context;
  }

  /**
   * Get entries for a specific date
   */
  getEntriesForDate(date: string): ActivityEntry[] {
    if (this.searchIndex) {
      return this.searchIndex.getByDate(date);
    }
    return this.context.entries.filter((e) => e.date === date);
  }

  /**
   * Fast full-text search using SQLite FTS5
   */
  searchFast(query: string, limit = 50): ActivityEntry[] {
    if (this.searchIndex) {
      return this.searchIndex.searchWeighted(query, limit);
    }
    // Fallback to in-memory search
    return this.search(query).slice(0, limit);
  }

  /**
   * Search entries by tags or text (simple keyword match, in-memory)
   */
  search(query: string): ActivityEntry[] {
    const q = query.toLowerCase();
    return this.context.entries.filter(
      (e) =>
        e.activity.toLowerCase().includes(q) ||
        e.details.toLowerCase().includes(q) ||
        e.summary?.toLowerCase().includes(q) ||
        (e.app?.name || e.application).toLowerCase().includes(q) ||
        e.tags.some((t) => t.toLowerCase().includes(q)) ||
        (e.browser?.url && e.browser.url.toLowerCase().includes(q)) ||
        (e.browser?.domain && e.browser.domain.toLowerCase().includes(q)) ||
        (e.video?.title && e.video.title.toLowerCase().includes(q)) ||
        (e.video?.channel && e.video.channel.toLowerCase().includes(q)) ||
        (e.ide?.currentFile && e.ide.currentFile.toLowerCase().includes(q)) ||
        (e.ide?.projectName && e.ide.projectName.toLowerCase().includes(q)) ||
        (e.terminal?.lastCommand && e.terminal.lastCommand.toLowerCase().includes(q))
    );
  }

  /**
   * Semantic search using LLM to find relevant activities
   */
  async semanticSearch(query: string, maxResults = 10): Promise<ActivityEntry[]> {
    if (this.context.entries.length === 0) {
      return [];
    }

    // Build a compact index of all entries for the LLM to search
    const entryIndex = this.context.entries.map((e, idx) => {
      const parts = [
        `[${idx}] ${e.date} ${e.time} - ${e.app?.name || e.application}`,
        e.activity,
        e.browser?.url ? `URL: ${e.browser.url}` : null,
        e.browser?.pageTitle ? `Page: ${e.browser.pageTitle}` : null,
        e.video?.title ? `Video: ${e.video.title}` : null,
        e.ide?.filePath || e.ide?.currentFile ? `File: ${e.ide.filePath || e.ide.currentFile}` : null,
        e.terminal?.lastCommand ? `Command: ${e.terminal.lastCommand}` : null,
        e.summary ? e.summary.slice(0, 200) : null,
        `Tags: ${e.tags.join(", ")}`,
      ].filter(Boolean);
      return parts.join(" | ");
    });

    this.agent.clearMessages();
    await this.agent.prompt(
      `You are a search assistant. Given a user query and a list of activity entries, return the indices of the most relevant entries.

USER QUERY: "${query}"

ACTIVITY ENTRIES:
${entryIndex.join("\n")}

Return a JSON array of entry indices (numbers) that best match the query, ordered by relevance (most relevant first). Return up to ${maxResults} results. Consider semantic meaning, not just keyword matches.

For example, if the query is "blog post about java and cli" and entry [42] mentions "Reading article about Java terminal applications on xam.dk", that's a match even though "blog" and "cli" aren't exact words in the entry.

Return ONLY a JSON array of numbers, e.g.: [42, 15, 7, 23]
If no entries match, return: []`
    );

    const messages = this.agent.state.messages;
    const assistantMessage = messages.find(
      (m): m is AgentMessage & { role: "assistant" } => m.role === "assistant"
    );

    if (!assistantMessage) {
      return [];
    }

    const textContent = assistantMessage.content.find(
      (c): c is { type: "text"; text: string } => c.type === "text"
    );
    if (!textContent) {
      return [];
    }

    try {
      let jsonText = textContent.text.trim();
      // Remove markdown code block if present
      if (jsonText.startsWith("```json")) {
        jsonText = jsonText.slice(7);
      }
      if (jsonText.startsWith("```")) {
        jsonText = jsonText.slice(3);
      }
      if (jsonText.endsWith("```")) {
        jsonText = jsonText.slice(0, -3);
      }

      const indices: number[] = JSON.parse(jsonText.trim());

      // Map indices back to entries
      return indices
        .filter((idx) => idx >= 0 && idx < this.context.entries.length)
        .map((idx) => this.context.entries[idx]);
    } catch {
      console.error("Failed to parse search results:", textContent.text);
      return [];
    }
  }

  /**
   * Get last processed timestamp
   */
  getLastProcessedTimestamp(): number | undefined {
    const last = this.context.entries[this.context.entries.length - 1];
    return last?.timestamp;
  }

  /**
   * Smart search using agent with tools - can handle complex queries like
   * "last month I looked up some article on creating sandboxes in typescript"
   */
  async agentSearch(
    query: string,
    onEvent?: (event: { type: string; content?: string; resultCount?: number }) => void
  ): Promise<{ answer: string; entries: ActivityEntry[] }> {
    if (!this.searchIndex) {
      throw new Error("Search index not enabled");
    }

    // Create a search agent with tools
    const searchTools = createSearchTools(this.searchIndex);
    const searchAgent = new Agent({
      initialState: {
        systemPrompt: `You are a search assistant for a personal activity tracker. The user has indexed screenshots of their computer activity and wants to find specific moments.

You have tools to search the activity index:
- search_fulltext: Fast keyword search across all fields
- search_by_date_range: Get activities within a date range
- search_by_date: Get activities for a specific date
- search_by_app: Get activities for a specific application
- search_combined: Combine date filtering with keywords
- list_apps: See what apps are indexed
- list_dates: See what dates have data
- get_index_stats: See index statistics

STRATEGY FOR COMPLEX QUERIES:
1. Parse the user's query to identify: time references, keywords, app names
2. If there's a time reference ("last month", "yesterday", "in January"), use date filtering first
3. Then apply keyword search within those results
4. Use multiple tool calls to narrow down results

Examples:
- "last month I looked up some article on typescript sandboxes"
  → First: search_by_date_range for last month
  → Then: search_fulltext for "typescript sandbox article"
  → Or: search_combined with both

- "what was I doing in VS Code yesterday"
  → search_combined with date=yesterday and appName="VS Code"

- "that github repo about AI agents"
  → search_fulltext for "github AI agents repository"

Today's date is ${new Date().toISOString().split("T")[0]}.

After finding results, summarize what you found for the user. If you find the specific thing they're looking for, highlight it.`,
        model: this.model,
        thinkingLevel: "off",
        tools: searchTools,
        messages: [],
      },
    });

    // Subscribe to events if callback provided
    if (onEvent) {
      searchAgent.subscribe((event) => {
        if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
          onEvent({ type: "text", content: event.assistantMessageEvent.delta });
        } else if (event.type === "tool_execution_start") {
          onEvent({ type: "tool_start", content: event.toolName });
          // Emit args
          const args = event.args;
          if (args && typeof args === "object") {
            onEvent({ type: "tool_args", content: JSON.stringify(args) });
          }
        } else if (event.type === "tool_execution_end") {
          // Extract result count and content
          const result = event.result;
          let resultContent = "";
          let resultCount = 0;
          if (result && typeof result === "object" && "content" in result) {
            const content = (result as { content?: Array<{ type: string; text?: string }> }).content;
            if (Array.isArray(content)) {
              const textBlock = content.find((c) => c.type === "text");
              if (textBlock && "text" in textBlock) {
                resultContent = textBlock.text || "";
              }
            }
            const details = (result as { details?: { count?: number } }).details;
            if (details && typeof details.count === "number") {
              resultCount = details.count;
            }
          }
          onEvent({ type: "tool_result", content: resultContent, resultCount });
        }
      });
    }

    await searchAgent.prompt(query);

    // Get the final response
    const messages = searchAgent.state.messages;
    const assistantMessages = messages.filter((m) => m.role === "assistant");
    const lastAssistant = assistantMessages[assistantMessages.length - 1];

    let answer = "";
    if (lastAssistant && "content" in lastAssistant) {
      const textContent = lastAssistant.content.find(
        (c): c is { type: "text"; text: string } => c.type === "text"
      );
      if (textContent) {
        answer = textContent.text;
      }
    }

    // Collect entries from tool results
    const entries: ActivityEntry[] = [];
    for (const msg of messages) {
      if (msg.role === "toolResult" && !msg.isError) {
        // Tool results contain formatted text, we'd need to track actual entries
        // For now, return empty - the answer contains the summary
      }
    }

    return { answer, entries };
  }

  /**
   * Process natural language feedback to update learned rules
   */
  async processFeedback(feedback: string): Promise<{ success: boolean; message: string; rulesChanged: boolean }> {
    const currentRules = this.rules;

    this.agent.clearMessages();
    await this.agent.prompt(
      `You are helping improve an activity indexing system. The user has provided feedback about how the system should work better.

CURRENT LEARNED RULES:
${JSON.stringify(currentRules, null, 2)}

USER FEEDBACK:
"${feedback}"

Based on this feedback, update the rules. There are THREE types of rules:
1. "indexing" - rules for how to extract/tag information (e.g., "For Obsidian, extract vault name and wiki links")
2. "search" - rules for search behavior like synonyms (e.g., "'CLI' should match 'terminal', 'command line'")
3. "exclude" - things to SKIP or NOT index (e.g., "Don't index terminal commands", "Skip system notifications")

Analyze the feedback and determine:
- Is this about indexing, search, or exclusion?
- Is the user asking to ADD a new rule, REMOVE an existing rule, or MODIFY one?
- What specific rule should be added/removed/modified?

Return JSON (no markdown):
{
  "understood": true/false,
  "interpretation": "What you understood from the feedback",
  "action": "add" | "remove" | "modify" | "none",
  "category": "indexing" | "search" | "exclude",
  "ruleIndex": null or index of rule to modify/remove (0-based),
  "previousRule": "the old rule text if modifying",
  "newRule": "The rule text to add or the new text if modifying",
  "updatedRules": {
    "indexing": ["full", "updated", "list"],
    "search": ["full", "updated", "list"],
    "exclude": ["full", "updated", "list"]
  }
}`
    );

    const messages = this.agent.state.messages;
    const assistantMessage = messages.find(
      (m): m is AgentMessage & { role: "assistant" } => m.role === "assistant"
    );

    if (!assistantMessage) {
      return { success: false, message: "No response from agent", rulesChanged: false };
    }

    const textContent = assistantMessage.content.find(
      (c): c is { type: "text"; text: string } => c.type === "text"
    );
    if (!textContent) {
      return { success: false, message: "No text content in response", rulesChanged: false };
    }

    try {
      let jsonText = textContent.text.trim();
      if (jsonText.startsWith("```json")) jsonText = jsonText.slice(7);
      if (jsonText.startsWith("```")) jsonText = jsonText.slice(3);
      if (jsonText.endsWith("```")) jsonText = jsonText.slice(0, -3);

      const result = JSON.parse(jsonText.trim());

      if (!result.understood) {
        return {
          success: false,
          message: `Could not understand feedback: ${result.interpretation}`,
          rulesChanged: false,
        };
      }

      if (result.action === "none") {
        return {
          success: true,
          message: result.interpretation,
          rulesChanged: false,
        };
      }

      // Record the change in history before applying
      recordRuleChange(this.rulesPath, {
        feedback,
        action: result.action,
        category: result.category,
        rule: result.newRule || result.previousRule,
        previousRule: result.previousRule,
        ruleIndex: result.ruleIndex,
      });

      // Update rules
      this.rules = {
        indexing: result.updatedRules.indexing || currentRules.indexing,
        search: result.updatedRules.search || currentRules.search,
        exclude: result.updatedRules.exclude || currentRules.exclude || [],
      };

      // Save to disk
      saveLearnedRules(this.rulesPath, this.rules);

      // Update agent's system prompt
      this.agent.setSystemPrompt(this.buildIndexingPrompt());

      const actionVerb = result.action === "add" ? "Added" : result.action === "remove" ? "Removed" : "Modified";
      return {
        success: true,
        message: `${result.interpretation}\n\n${actionVerb} ${result.category} rule: "${result.newRule || result.previousRule}"`,
        rulesChanged: true,
      };
    } catch (e) {
      console.error("Failed to parse feedback response:", textContent.text);
      return { success: false, message: `Failed to process feedback: ${e}`, rulesChanged: false };
    }
  }

  /**
   * Undo the last rule change
   */
  undoLastChange(): { success: boolean; message: string } {
    const result = undoLastChange(this.rulesPath);
    if (result.success) {
      // Reload rules and update prompt
      this.rules = loadLearnedRules(this.rulesPath);
      this.agent.setSystemPrompt(this.buildIndexingPrompt());
    }
    return result;
  }

  /**
   * Get rules history
   */
  getHistory(): RulesHistory {
    return loadRulesHistory(this.rulesPath);
  }

  /**
   * Show current rules
   */
  showRules(): string {
    const lines: string[] = ["Current Learned Rules:", ""];

    if (this.rules.indexing.length > 0) {
      lines.push("INDEXING RULES (what to extract):");
      this.rules.indexing.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
      lines.push("");
    }

    if (this.rules.exclude.length > 0) {
      lines.push("EXCLUDE RULES (what to skip):");
      this.rules.exclude.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
      lines.push("");
    }

    if (this.rules.search.length > 0) {
      lines.push("SEARCH RULES (synonyms/matching):");
      this.rules.search.forEach((r, i) => lines.push(`  ${i + 1}. ${r}`));
      lines.push("");
    }

    const hasRules = this.rules.indexing.length > 0 || this.rules.search.length > 0 || this.rules.exclude.length > 0;
    if (!hasRules) {
      lines.push("No learned rules yet. Use 'feedback' command to teach the agent.");
    }

    return lines.join("\n");
  }

  /**
   * Show rules change history
   */
  showHistory(): string {
    const history = this.getHistory();
    if (history.changes.length === 0) {
      return "No rule changes recorded yet.";
    }

    const lines: string[] = ["Rules Change History:", ""];

    for (const change of history.changes.slice().reverse()) {
      const date = new Date(change.timestamp).toLocaleString();
      lines.push(`[${date}] ${change.action.toUpperCase()} ${change.category}`);
      lines.push(`  Rule: "${change.rule}"`);
      lines.push(`  Feedback: "${change.feedback}"`);
      if (change.previousRule) {
        lines.push(`  Previous: "${change.previousRule}"`);
      }
      lines.push("");
    }

    return lines.join("\n");
  }

  /**
   * Sync all entries from JSON context to SQLite index
   */
  syncToSearchIndex(): { synced: number; skipped: number } {
    if (!this.searchIndex) {
      return { synced: 0, skipped: 0 };
    }

    let synced = 0;
    let skipped = 0;

    for (const entry of this.context.entries) {
      if (!this.searchIndex.hasEntry(entry.filename)) {
        this.searchIndex.indexEntry(entry);
        synced++;
      } else {
        skipped++;
      }
    }

    return { synced, skipped };
  }

  /**
   * Rebuild the entire search index from JSON context
   */
  rebuildSearchIndex(): number {
    if (!this.searchIndex) {
      return 0;
    }

    this.searchIndex.clear();
    this.searchIndex.indexEntries(this.context.entries);
    this.searchIndex.rebuildIndex();

    return this.context.entries.length;
  }

  /**
   * Get search index stats
   */
  getSearchIndexStats(): { entries: number; apps: number; dates: number; dbSizeBytes: number } | null {
    if (!this.searchIndex) {
      return null;
    }
    return this.searchIndex.getStats();
  }

  /**
   * Get all unique app names from the index
   */
  getApps(): string[] {
    if (this.searchIndex) {
      return this.searchIndex.getApps();
    }
    const apps = new Set<string>();
    for (const e of this.context.entries) {
      apps.add(e.app?.name || e.application);
    }
    return Array.from(apps).sort();
  }

  /**
   * Get all unique dates from the index
   */
  getDates(): string[] {
    if (this.searchIndex) {
      return this.searchIndex.getDates();
    }
    const dates = new Set<string>();
    for (const e of this.context.entries) {
      dates.add(e.date);
    }
    return Array.from(dates).sort().reverse();
  }

  /**
   * Get entries by app name
   */
  getEntriesByApp(appName: string): ActivityEntry[] {
    if (this.searchIndex) {
      return this.searchIndex.getByApp(appName);
    }
    return this.context.entries.filter((e) => (e.app?.name || e.application) === appName);
  }

  /**
   * Get entries by date range
   */
  getEntriesByDateRange(startDate: string, endDate: string): ActivityEntry[] {
    if (this.searchIndex) {
      return this.searchIndex.getByDateRange(startDate, endDate);
    }
    return this.context.entries.filter((e) => e.date >= startDate && e.date <= endDate);
  }

  /**
   * Close the search index (call when done)
   */
  close(): void {
    if (this.searchIndex) {
      this.searchIndex.close();
      this.searchIndex = null;
    }
  }

  /**
   * Create a chat agent for interactive conversation
   * Returns an agent with search tools and feedback capabilities
   */
  createChatAgent(): Agent {
    if (!this.searchIndex) {
      throw new Error("Search index not enabled");
    }

    const searchTools = createSearchTools(this.searchIndex);
    
    // Add feedback tool
    const feedbackTool: AgentTool = {
      name: "update_rules",
      label: "Update Rules",
      description: "Update indexing or search rules based on user feedback. Use this when the user wants to teach the system something new, like 'remember that for VS Code always note the git branch' or 'CLI should match terminal'.",
      parameters: Type.Object({
        feedback: Type.String({ description: "The user's feedback about how to improve indexing or search" })
      }),
      execute: async (_toolCallId, rawParams) => {
        const params = rawParams as { feedback: string };
        const result = await this.processFeedback(params.feedback);
        return {
          content: [{ type: "text" as const, text: result.message }],
          details: { success: result.success }
        };
      }
    };

    const showRulesTool: AgentTool = {
      name: "show_rules",
      label: "Show Rules",
      description: "Show the current learned rules for indexing and search",
      parameters: Type.Object({}),
      execute: async (_toolCallId) => {
        return {
          content: [{ type: "text" as const, text: this.showRules() }],
          details: {}
        };
      }
    };

    const undoTool: AgentTool = {
      name: "undo_rule_change",
      label: "Undo Rule Change",
      description: "Undo the last rule change",
      parameters: Type.Object({}),
      execute: async (_toolCallId) => {
        const result = this.undoLastChange();
        return {
          content: [{ type: "text" as const, text: result.message }],
          details: { success: result.success }
        };
      }
    };

    const statusTool: AgentTool = {
      name: "get_status",
      label: "Get Status",
      description: "Get the current status of the activity index (number of screenshots, entries, etc)",
      parameters: Type.Object({}),
      execute: async (_toolCallId) => {
        const stats = this.getSearchIndexStats();
        const entryCount = this.context.entries.length;
        const lastProcessed = this.context.lastProcessed || "None";
        
        let text = `Activity Index Status:\n`;
        text += `- Total entries: ${entryCount}\n`;
        text += `- Last processed: ${lastProcessed}\n`;
        if (stats) {
          text += `- Apps tracked: ${stats.apps}\n`;
          text += `- Days of data: ${stats.dates}\n`;
          text += `- Index size: ${(stats.dbSizeBytes / 1024).toFixed(1)} KB\n`;
        }
        return {
          content: [{ type: "text" as const, text }],
          details: { entryCount }
        };
      }
    };

    const allTools: AgentTool[] = [...searchTools, feedbackTool, showRulesTool, undoTool, statusTool];

    const chatAgent = new Agent({
      initialState: {
        systemPrompt: `You are a helpful assistant for searching and managing a personal activity tracker. The user has indexed screenshots of their computer activity.

You can:
1. SEARCH - Find past activities using various search tools
2. TEACH - Learn new rules about how to index or search (use update_rules)
3. MANAGE - Show current rules, undo changes, check status

SEARCH TOOLS:
- search_fulltext: Fast keyword search
- search_by_date_range: Activities within a date range  
- search_by_date: Activities for a specific date
- search_by_app: Activities for a specific app
- search_combined: Combine date + keywords + app
- list_apps: See what apps are indexed
- list_dates: See what dates have data

MANAGEMENT TOOLS:
- update_rules: Learn new indexing/search rules from feedback
- show_rules: Display current learned rules
- undo_rule_change: Revert the last rule change
- get_status: Show index statistics

For search queries, be smart about parsing:
- "yesterday" = ${new Date(Date.now() - 86400000).toISOString().split("T")[0]}
- "last week" = date range for past 7 days
- "in VS Code" = filter by app

Today's date is ${new Date().toISOString().split("T")[0]}.

Be conversational but concise. When showing search results, summarize what you found.`,
        model: this.model,
        thinkingLevel: "off",
        tools: allTools,
        messages: [],
      },
    });

    return chatAgent;
  }

  /**
   * Chat with conversation history support
   * history is an array of {role: "user"|"assistant", content: string}
   */
  async chat(
    message: string,
    history: Array<{ role: "user" | "assistant"; content: string }> = [],
    onEvent?: (event: { type: string; content?: string }) => void
  ): Promise<string> {
    // Build prompt with history context
    let prompt = message;
    
    if (history.length > 0) {
      // Format history as context in the prompt
      const historyText = history.map(msg => {
        const role = msg.role === "user" ? "User" : "Assistant";
        // Truncate long messages to save tokens
        const content = msg.content.length > 500 
          ? msg.content.slice(0, 500) + "..." 
          : msg.content;
        return `${role}: ${content}`;
      }).join("\n\n");
      
      prompt = `Previous conversation:\n${historyText}\n\nUser: ${message}`;
    }
    
    const chatAgent = this.createChatAgent();

    if (onEvent) {
      chatAgent.subscribe((event) => {
        if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
          onEvent({ type: "text", content: event.assistantMessageEvent.delta });
        } else if (event.type === "tool_execution_start") {
          onEvent({ type: "tool_start", content: event.toolName });
        } else if (event.type === "tool_execution_end") {
          onEvent({ type: "tool_end", content: event.toolName });
        }
      });
    }

    await chatAgent.prompt(prompt);

    // Get the final response
    const messages = chatAgent.state.messages;
    const assistantMessages = messages.filter((m) => m.role === "assistant");
    const lastAssistant = assistantMessages[assistantMessages.length - 1];

    if (lastAssistant && "content" in lastAssistant) {
      const textContent = lastAssistant.content.find(
        (c): c is { type: "text"; text: string } => c.type === "text"
      );
      if (textContent) {
        return textContent.text;
      }
    }

    return "No response";
  }

  // ============================================================
  // User Profile Methods
  // ============================================================

  /**
   * Get the current user profile content
   */
  getProfile(): string {
    return this.profileManager.getProfile();
  }

  /**
   * Get profile update history
   */
  getProfileHistory(): ProfileHistory {
    return this.profileManager.getHistory();
  }

  /**
   * Get recent profile edits for display
   */
  getRecentProfileEdits(count = 10): ProfileEdit[] {
    return this.profileManager.getRecentEdits(count);
  }

  /**
   * Format profile history for display
   */
  formatProfileHistory(count = 10): string {
    return this.profileManager.formatHistory(count);
  }

  /**
   * Update the user profile based on recent activity
   * 
   * @param hoursBack - How many hours of activity to analyze (default: 1)
   * @param onEvent - Optional callback for streaming events
   */
  async updateProfile(
    hoursBack = 1,
    onEvent?: (event: { type: string; content?: string }) => void
  ): Promise<{ success: boolean; summary: string; changed: boolean; entriesAnalyzed: number }> {
    // Get entries from the last N hours
    const cutoffTime = Date.now() - (hoursBack * 60 * 60 * 1000);
    const recentEntries = this.context.entries.filter(e => e.timestamp >= cutoffTime);

    if (recentEntries.length === 0) {
      return {
        success: true,
        summary: `No activities found in the last ${hoursBack} hour(s)`,
        changed: false,
        entriesAnalyzed: 0,
      };
    }

    const result = await this.profileManager.updateProfile(recentEntries, onEvent);
    
    return {
      ...result,
      entriesAnalyzed: recentEntries.length,
    };
  }

  /**
   * Update the user profile based on entries from a specific date range
   */
  async updateProfileForDateRange(
    startDate: string,
    endDate: string,
    onEvent?: (event: { type: string; content?: string }) => void
  ): Promise<{ success: boolean; summary: string; changed: boolean; entriesAnalyzed: number }> {
    const entries = this.getEntriesByDateRange(startDate, endDate);

    if (entries.length === 0) {
      return {
        success: true,
        summary: `No activities found between ${startDate} and ${endDate}`,
        changed: false,
        entriesAnalyzed: 0,
      };
    }

    const result = await this.profileManager.updateProfile(entries, onEvent);
    
    return {
      ...result,
      entriesAnalyzed: entries.length,
    };
  }

  /**
   * Restore profile to a previous version from history
   * @param editIndex - Index of edit to restore to (0 = most recent)
   */
  restoreProfileFromHistory(editIndex: number): { success: boolean; message: string } {
    return this.profileManager.restoreFromHistory(editIndex);
  }

  /**
   * Get timestamp of last profile update
   */
  getLastProfileUpdateTimestamp(): string | undefined {
    return this.profileManager.getLastUpdateTimestamp();
  }

  /**
   * Rebuild profile from scratch using all indexed entries.
   * Resets the profile to default first, then updates with all data.
   */
  async rebuildProfile(): Promise<{ success: boolean; summary: string; changed: boolean; entriesAnalyzed: number }> {
    // Reset to default
    this.profileManager.resetProfile();

    const entries = this.context.entries;
    if (entries.length === 0) {
      return { success: true, summary: "No entries to build from", changed: false, entriesAnalyzed: 0 };
    }

    const result = await this.profileManager.updateProfile(entries);
    return { ...result, entriesAnalyzed: entries.length };
  }

  /**
   * Check if profile update is due (based on time since last update)
   * @param intervalHours - How often to update (default: 1 hour)
   */
  isProfileUpdateDue(intervalHours = 1): boolean {
    const lastUpdate = this.profileManager.getLastUpdateTimestamp();
    if (!lastUpdate) return true;
    
    const lastUpdateTime = new Date(lastUpdate).getTime();
    const timeSinceUpdate = Date.now() - lastUpdateTime;
    const intervalMs = intervalHours * 60 * 60 * 1000;
    
    return timeSinceUpdate >= intervalMs;
  }
}
