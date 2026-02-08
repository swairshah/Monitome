// Types
export type { ActivityEntry, ActivitySession, ActivityContext, ScreenshotInfo } from "./types.js";

// Core agent
export { ActivityAgent } from "./activity-agent.js";

// Screenshot utilities
export {
  parseScreenshotFilename,
  listScreenshots,
  getScreenshotsAfter,
  getRecordingsDir,
  groupScreenshotsByDate,
} from "./screenshot-parser.js";

// Learned rules
export {
  loadLearnedRules,
  saveLearnedRules,
  formatIndexingRules,
  formatSearchRules,
  loadRulesHistory,
  recordRuleChange,
  undoLastChange,
  type LearnedRules,
  type RulesHistory,
  type RuleChange,
} from "./learned-rules.js";

// Search index
export { SearchIndex } from "./search-index.js";

// Search tools
export { createSearchTools } from "./search-tools.js";

// User profile
export {
  UserProfileManager,
  type ProfileEdit,
  type ProfileHistory,
} from "./user-profile.js";
