import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { join, dirname } from "path";
import { Agent, type AgentMessage } from "@mariozechner/pi-agent-core";
import type { Model } from "@mariozechner/pi-ai";
import type { ActivityEntry } from "./types.js";

/**
 * A single profile edit record
 */
export interface ProfileEdit {
  /** ISO timestamp of the edit */
  timestamp: string;
  /** What changed (summary) */
  summary: string;
  /** The full profile content before this edit */
  previousContent: string;
  /** The full profile content after this edit */
  newContent: string;
  /** Number of activities analyzed for this update */
  activitiesAnalyzed: number;
  /** Date range of activities analyzed */
  activityRange: {
    start: string;
    end: string;
  };
}

/**
 * Profile history stored in JSON
 */
export interface ProfileHistory {
  edits: ProfileEdit[];
  lastUpdateTimestamp?: string;
}

const DEFAULT_PROFILE = `# About Me

*I'm learning who you are by watching what you do. This will fill in as I observe more.*

## What I'm Working On

- *Nothing yet — let me watch for a bit.*

## Things Worth Revisiting

- *I'll note things here that seemed important or unfinished.*

## What I'm Into

- *Still figuring this out.*

## Tools & Stack

- *Waiting to see what you reach for.*

## Reading & Watching

- *I'll track articles, videos, docs that come up.*

## Open Threads

- *Half-finished explorations, rabbit holes, things left mid-thought.*

---
*Last updated: Never*
`;

const PROFILE_UPDATE_PROMPT = `You are the user's second brain. You watch their screen activity and maintain a living document — not a dry profile, but a working understanding of who they are, what they're doing, and what they might want to come back to.

Write as if you ARE learning this material alongside them. You're a study partner who's been watching over their shoulder and is keeping notes for both of you.

Your voice should be:
- First person plural ("we spent a while on...", "might want to revisit...") or second person ("you were deep in...")
- Specific and concrete — actual project names, URLs, file paths, exact topics
- Honest about depth — "skimmed" vs "spent 2 hours on" vs "kept coming back to"
- Forward-looking — "might want to re-read that blog post about X" or "left off mid-way through Y"

Maintain these sections:

1. **What I'm Working On** — Current projects, tasks, active areas. Include time estimates ("spent most of the afternoon on...", "quick 10-min check on..."). Demote or archive things that haven't shown up recently.

2. **Things Worth Revisiting** — Stuff that seemed important but was only briefly touched. Blog posts that were skimmed. Docs that were opened but not finished. Errors that were worked around but not understood. Write these as actionable nudges: "Re-read that post on X — only got halfway", "The bug in Y might be related to Z, worth digging into".

3. **What I'm Into** — Broader interests, recurring themes, rabbit holes. Not just "likes TypeScript" but "has been going deep on building CLI tools in TypeScript, specifically around agent architectures and TUI frameworks".

4. **Tools & Stack** — What they actually use day-to-day. Languages, editors, terminals, frameworks. Note new additions ("just started using Bun alongside Node").

5. **Reading & Watching** — Specific articles, videos, docs, blog posts. Track what was consumed and what's worth returning to. Include titles, authors, URLs when available.

6. **Open Threads** — Half-finished things. Tabs that were left open. Code that was abandoned mid-refactor. Research that trailed off. These are breadcrumbs for future sessions.

RULES:
- Be specific, not generic. "Working on Monitome's activity-agent profile feature" not "Working on a project".
- Track depth and duration. "Spent a solid chunk of time" vs "briefly glanced at".
- Note transitions and context switches — they reveal priorities and interruptions.
- When something keeps appearing across sessions, call it out explicitly.
- When something disappears, move it to Open Threads or drop it.
- Keep the tone warm but not sycophantic. You're a sharp study partner, not a cheerleader.
- Use bullet points, keep it scannable. This should be useful at a glance.
- Don't pad with filler. If a section has nothing new, leave it as-is.`;

/**
 * Manages user profile based on activity patterns
 */
export class UserProfileManager {
  private dataDir: string;
  private profilePath: string;
  private historyPath: string;
  private model: Model<any>;

  constructor(dataDir: string, model: Model<any>) {
    this.dataDir = dataDir;
    this.profilePath = join(dataDir, "user-profile.md");
    this.historyPath = join(dataDir, "profile-history.json");
    this.model = model;
  }

  /**
   * Get the current profile content
   */
  getProfile(): string {
    if (existsSync(this.profilePath)) {
      return readFileSync(this.profilePath, "utf-8");
    }
    return DEFAULT_PROFILE;
  }

  /**
   * Save profile to disk
   */
  private saveProfile(content: string): void {
    const dir = dirname(this.profilePath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(this.profilePath, content);
  }

  /**
   * Reset profile to default (blank slate)
   */
  resetProfile(): void {
    this.saveProfile(DEFAULT_PROFILE);
  }

  /**
   * Get profile history
   */
  getHistory(): ProfileHistory {
    if (existsSync(this.historyPath)) {
      try {
        return JSON.parse(readFileSync(this.historyPath, "utf-8"));
      } catch {
        return { edits: [] };
      }
    }
    return { edits: [] };
  }

  /**
   * Save profile history to disk
   */
  private saveHistory(history: ProfileHistory): void {
    const dir = dirname(this.historyPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(this.historyPath, JSON.stringify(history, null, 2));
  }

  /**
   * Record a profile edit in history
   */
  private recordEdit(edit: ProfileEdit): void {
    const history = this.getHistory();
    history.edits.push(edit);
    history.lastUpdateTimestamp = edit.timestamp;
    
    // Keep last 100 edits max
    if (history.edits.length > 100) {
      history.edits = history.edits.slice(-100);
    }
    
    this.saveHistory(history);
  }

  /**
   * Get the timestamp of the last profile update
   */
  getLastUpdateTimestamp(): string | undefined {
    return this.getHistory().lastUpdateTimestamp;
  }

  /**
   * Update the profile based on recent activity entries
   * 
   * @param entries - Activity entries to analyze (should be recent, e.g., last hour or day)
   * @param onEvent - Optional callback for streaming events
   * @returns Summary of what changed
   */
  async updateProfile(
    entries: ActivityEntry[],
    onEvent?: (event: { type: string; content?: string }) => void
  ): Promise<{ success: boolean; summary: string; changed: boolean }> {
    if (entries.length === 0) {
      return {
        success: true,
        summary: "No activities to analyze",
        changed: false,
      };
    }

    const currentProfile = this.getProfile();
    
    // Format entries for the prompt
    const activitySummary = entries.map((e) => {
      const parts = [
        `[${e.date} ${e.time}] ${e.app?.name || e.application}`,
        e.activity,
      ];
      if (e.browser?.url) parts.push(`URL: ${e.browser.url}`);
      if (e.browser?.pageTitle) parts.push(`Page: ${e.browser.pageTitle}`);
      if (e.video?.title) parts.push(`Video: "${e.video.title}" by ${e.video.channel || "unknown"}`);
      if (e.ide?.projectName) parts.push(`Project: ${e.ide.projectName}`);
      if (e.ide?.currentFile) parts.push(`File: ${e.ide.currentFile}`);
      if (e.ide?.language) parts.push(`Language: ${e.ide.language}`);
      if (e.terminal?.lastCommand) parts.push(`Command: ${e.terminal.lastCommand}`);
      if (e.tags.length > 0) parts.push(`Tags: ${e.tags.join(", ")}`);
      return parts.join(" | ");
    }).join("\n");

    // Get date range
    const dates = entries.map(e => e.date).sort();
    const times = entries.map(e => `${e.date} ${e.time}`).sort();
    const activityRange = {
      start: times[0] || "",
      end: times[times.length - 1] || "",
    };

    const agent = new Agent({
      initialState: {
        systemPrompt: PROFILE_UPDATE_PROMPT,
        model: this.model,
        thinkingLevel: "off",
        tools: [],
        messages: [],
      },
    });

    if (onEvent) {
      agent.subscribe((event) => {
        if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
          onEvent({ type: "text", content: event.assistantMessageEvent.delta });
        }
      });
    }

    const prompt = `Here's the profile as it stands now:

\`\`\`markdown
${currentProfile}
\`\`\`

Here's what happened recently (${entries.length} screenshots from ${activityRange.start} to ${activityRange.end}):

${activitySummary}

Look at what actually happened in this session. Update the profile like you're catching up your notes after watching someone work. What did they spend time on? What was just a drive-by glance? Did they leave anything half-finished? Is there something they keep coming back to?

Merge this into the existing profile — don't blow away things that are still relevant, but evolve it. If something is clearly done or stale, archive it or drop it.

Return your response in this exact JSON format:

{
  "summary": "Brief description of what changed (1-2 sentences)",
  "changed": true/false,
  "updatedProfile": "The full updated markdown profile content"
}

If there's nothing meaningful to update (e.g. just idle/lock screens), set changed to false and return the profile unchanged.
The updatedProfile should be complete markdown, not just the changed parts.
Update the "Last updated" line at the bottom with: ${new Date().toISOString().split("T")[0]}.`;

    await agent.prompt(prompt);

    // Get the response
    const messages = agent.state.messages;
    const assistantMessage = messages.find(
      (m): m is AgentMessage & { role: "assistant" } => m.role === "assistant"
    );

    if (!assistantMessage) {
      return {
        success: false,
        summary: "No response from agent",
        changed: false,
      };
    }

    const textContent = assistantMessage.content.find(
      (c): c is { type: "text"; text: string } => c.type === "text"
    );

    if (!textContent) {
      return {
        success: false,
        summary: "No text content in response",
        changed: false,
      };
    }

    try {
      // Parse JSON response
      let jsonText = textContent.text.trim();
      if (jsonText.startsWith("```json")) jsonText = jsonText.slice(7);
      if (jsonText.startsWith("```")) jsonText = jsonText.slice(3);
      if (jsonText.endsWith("```")) jsonText = jsonText.slice(0, -3);

      const result = JSON.parse(jsonText.trim());

      if (result.changed && result.updatedProfile) {
        // Record the edit in history
        this.recordEdit({
          timestamp: new Date().toISOString(),
          summary: result.summary,
          previousContent: currentProfile,
          newContent: result.updatedProfile,
          activitiesAnalyzed: entries.length,
          activityRange,
        });

        // Save the new profile
        this.saveProfile(result.updatedProfile);
      }

      return {
        success: true,
        summary: result.summary,
        changed: result.changed,
      };
    } catch (e) {
      console.error("Failed to parse profile update response:", textContent.text);
      return {
        success: false,
        summary: `Failed to parse response: ${e}`,
        changed: false,
      };
    }
  }

  /**
   * Get recent edits (for display)
   */
  getRecentEdits(count = 10): ProfileEdit[] {
    const history = this.getHistory();
    return history.edits.slice(-count).reverse();
  }

  /**
   * Format profile history for display
   */
  formatHistory(count = 10): string {
    const edits = this.getRecentEdits(count);
    
    if (edits.length === 0) {
      return "No profile updates yet.";
    }

    const lines: string[] = ["Profile Update History:", ""];

    for (const edit of edits) {
      const date = new Date(edit.timestamp).toLocaleString();
      lines.push(`[${date}]`);
      lines.push(`  Activities: ${edit.activitiesAnalyzed} (${edit.activityRange.start} → ${edit.activityRange.end})`);
      lines.push(`  Changes: ${edit.summary}`);
      lines.push("");
    }

    return lines.join("\n");
  }

  /**
   * Restore profile to a previous state from history
   */
  restoreFromHistory(editIndex: number): { success: boolean; message: string } {
    const history = this.getHistory();
    
    // Convert from reverse index (0 = most recent) to actual index
    const actualIndex = history.edits.length - 1 - editIndex;
    
    if (actualIndex < 0 || actualIndex >= history.edits.length) {
      return {
        success: false,
        message: `Invalid edit index. Valid range: 0-${history.edits.length - 1}`,
      };
    }

    const edit = history.edits[actualIndex];
    
    // Restore the previous content
    this.saveProfile(edit.previousContent);
    
    // Record this as a new edit
    this.recordEdit({
      timestamp: new Date().toISOString(),
      summary: `Restored to version from ${edit.timestamp}`,
      previousContent: this.getProfile(),
      newContent: edit.previousContent,
      activitiesAnalyzed: 0,
      activityRange: { start: "", end: "" },
    });

    return {
      success: true,
      message: `Restored profile to version from ${new Date(edit.timestamp).toLocaleString()}`,
    };
  }
}
