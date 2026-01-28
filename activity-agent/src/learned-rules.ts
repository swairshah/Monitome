import { readFileSync, writeFileSync, existsSync, mkdirSync } from "fs";
import { dirname, join } from "path";

/**
 * A single rule change in history
 */
export interface RuleChange {
  /** Unique ID for this change */
  id: string;
  /** Timestamp of the change */
  timestamp: number;
  /** The original feedback that triggered this change */
  feedback: string;
  /** What action was taken */
  action: "add" | "remove" | "modify";
  /** Which rule category */
  category: "indexing" | "search" | "exclude";
  /** The rule text that was added/removed/modified */
  rule: string;
  /** Previous rule text if modified */
  previousRule?: string;
  /** Index in the array if applicable */
  ruleIndex?: number;
}

/**
 * Learned rules from user feedback
 */
export interface LearnedRules {
  /** Rules for how to index/extract information from screenshots */
  indexing: string[];
  /** Rules for search behavior (synonyms, expansions) */
  search: string[];
  /** Rules for what to EXCLUDE or ignore during indexing */
  exclude: string[];
  /** Timestamp of last update */
  lastUpdated?: number;
}

/**
 * History of all rule changes
 */
export interface RulesHistory {
  changes: RuleChange[];
}

const DEFAULT_RULES: LearnedRules = {
  indexing: [],
  search: [],
  exclude: [],
};

const DEFAULT_HISTORY: RulesHistory = {
  changes: [],
};

/**
 * Generate a unique ID for a rule change
 */
function generateChangeId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

/**
 * Load learned rules from disk
 */
export function loadLearnedRules(rulesPath: string): LearnedRules {
  if (existsSync(rulesPath)) {
    try {
      const data = readFileSync(rulesPath, "utf-8");
      return { ...DEFAULT_RULES, ...JSON.parse(data) };
    } catch {
      return { ...DEFAULT_RULES };
    }
  }
  return { ...DEFAULT_RULES };
}

/**
 * Save learned rules to disk
 */
export function saveLearnedRules(rulesPath: string, rules: LearnedRules): void {
  const dir = dirname(rulesPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  rules.lastUpdated = Date.now();
  writeFileSync(rulesPath, JSON.stringify(rules, null, 2));
}

/**
 * Get the history file path from rules path
 */
export function getHistoryPath(rulesPath: string): string {
  const dir = dirname(rulesPath);
  return join(dir, "rules-history.json");
}

/**
 * Load rules history from disk
 */
export function loadRulesHistory(rulesPath: string): RulesHistory {
  const historyPath = getHistoryPath(rulesPath);
  if (existsSync(historyPath)) {
    try {
      const data = readFileSync(historyPath, "utf-8");
      return JSON.parse(data);
    } catch {
      return { ...DEFAULT_HISTORY };
    }
  }
  return { ...DEFAULT_HISTORY };
}

/**
 * Save rules history to disk
 */
export function saveRulesHistory(rulesPath: string, history: RulesHistory): void {
  const historyPath = getHistoryPath(rulesPath);
  const dir = dirname(historyPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(historyPath, JSON.stringify(history, null, 2));
}

/**
 * Record a rule change in history
 */
export function recordRuleChange(
  rulesPath: string,
  change: Omit<RuleChange, "id" | "timestamp">
): RuleChange {
  const history = loadRulesHistory(rulesPath);
  const fullChange: RuleChange = {
    ...change,
    id: generateChangeId(),
    timestamp: Date.now(),
  };
  history.changes.push(fullChange);
  saveRulesHistory(rulesPath, history);
  return fullChange;
}

/**
 * Undo the last rule change
 */
export function undoLastChange(rulesPath: string): { success: boolean; message: string; undoneChange?: RuleChange } {
  const history = loadRulesHistory(rulesPath);
  const rules = loadLearnedRules(rulesPath);

  if (history.changes.length === 0) {
    return { success: false, message: "No changes to undo" };
  }

  const lastChange = history.changes.pop()!;

  // Reverse the change
  switch (lastChange.action) {
    case "add": {
      // Remove the added rule
      const arr = rules[lastChange.category];
      const idx = arr.indexOf(lastChange.rule);
      if (idx !== -1) {
        arr.splice(idx, 1);
      }
      break;
    }
    case "remove": {
      // Re-add the removed rule
      const arr = rules[lastChange.category];
      if (lastChange.ruleIndex !== undefined && lastChange.ruleIndex <= arr.length) {
        arr.splice(lastChange.ruleIndex, 0, lastChange.rule);
      } else {
        arr.push(lastChange.rule);
      }
      break;
    }
    case "modify": {
      // Restore the previous rule
      if (lastChange.previousRule !== undefined && lastChange.ruleIndex !== undefined) {
        rules[lastChange.category][lastChange.ruleIndex] = lastChange.previousRule;
      }
      break;
    }
  }

  saveLearnedRules(rulesPath, rules);
  saveRulesHistory(rulesPath, history);

  return {
    success: true,
    message: `Undone: ${lastChange.action} "${lastChange.rule}" in ${lastChange.category}`,
    undoneChange: lastChange,
  };
}

/**
 * Format rules for injection into the indexing prompt
 */
export function formatIndexingRules(rules: LearnedRules): string {
  const parts: string[] = [];

  if (rules.indexing.length > 0) {
    parts.push(`ADDITIONAL INDEXING RULES (learned from user feedback):
${rules.indexing.map((r, i) => `${i + 1}. ${r}`).join("\n")}`);
  }

  if (rules.exclude.length > 0) {
    parts.push(`DO NOT INDEX / EXCLUDE:
${rules.exclude.map((r, i) => `${i + 1}. ${r}`).join("\n")}`);
  }

  return parts.length > 0 ? "\n\n" + parts.join("\n\n") : "";
}

/**
 * Format rules for injection into the search prompt
 */
export function formatSearchRules(rules: LearnedRules): string {
  if (rules.search.length === 0) {
    return "";
  }
  return `\n\nSEARCH RULES (learned from user feedback):
${rules.search.map((r, i) => `${i + 1}. ${r}`).join("\n")}`;
}
