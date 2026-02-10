/**
 * Application-specific metadata
 */
export interface AppMetadata {
  /** Application name */
  name: string;
  /** Bundle ID or binary path if visible (e.g., /Applications/Visual Studio Code.app) */
  bundleOrPath?: string;
  /** Window title if visible */
  windowTitle?: string;
  /** Application category */
  category: "browser" | "ide" | "terminal" | "media" | "communication" | "productivity" | "design" | "system" | "other";
}

/**
 * Browser-specific metadata
 */
export interface BrowserMetadata {
  /** Browser name (Chrome, Safari, Firefox, Arc, etc.) */
  browser: string;
  /** Full URL from address bar */
  url?: string;
  /** Domain extracted from URL */
  domain?: string;
  /** Page title */
  pageTitle?: string;
  /** Type of page */
  pageType: "video" | "article" | "social" | "search" | "documentation" | "code" | "email" | "chat" | "shopping" | "other";
}

/**
 * Video-specific metadata (YouTube, Vimeo, etc.)
 */
export interface VideoMetadata {
  /** Platform (YouTube, Vimeo, Netflix, etc.) */
  platform: string;
  /** Video title */
  title?: string;
  /** Channel/creator name */
  channel?: string;
  /** Video duration if visible (e.g., "12:34") */
  duration?: string;
  /** Current playback position if visible */
  position?: string;
  /** Whether video is playing or paused */
  state?: "playing" | "paused" | "buffering" | "ended";
}

/**
 * IDE/Editor-specific metadata
 */
export interface IdeMetadata {
  /** IDE name (VS Code, Xcode, IntelliJ, etc.) */
  ide: string;
  /** Current file being edited */
  currentFile?: string;
  /** File path if visible */
  filePath?: string;
  /** Programming language */
  language?: string;
  /** Project/workspace name */
  projectName?: string;
  /** Git branch if visible */
  gitBranch?: string;
}

/**
 * Terminal-specific metadata
 */
export interface TerminalMetadata {
  /** Terminal app (Terminal, iTerm, Warp, etc.) */
  terminal: string;
  /** Current working directory if visible */
  cwd?: string;
  /** Last command visible */
  lastCommand?: string;
  /** Shell type if identifiable (bash, zsh, fish) */
  shell?: string;
  /** SSH connection if visible */
  sshHost?: string;
}

/**
 * Communication app metadata
 */
export interface CommunicationMetadata {
  /** App name (Slack, Discord, Messages, etc.) */
  app: string;
  /** Current channel/conversation */
  channel?: string;
  /** Person/group being chatted with */
  recipient?: string;
  /** Type of communication */
  type: "chat" | "video-call" | "voice-call" | "email";
}

/**
 * Document/productivity metadata
 */
export interface DocumentMetadata {
  /** App name (Pages, Word, Notion, etc.) */
  app: string;
  /** Document title */
  documentTitle?: string;
  /** Document type */
  documentType?: "text" | "spreadsheet" | "presentation" | "pdf" | "notes";
}

/**
 * A single activity layer within a screenshot.
 * Screenshots can contain multiple overlapping UI layers (e.g., a browser with a FaceTime overlay).
 */
export interface Activity {
  /** Whether this is the primary focused content or an overlay (notification, PiP, call popup, etc.) */
  layer: "primary" | "overlay";
  /** Application metadata for this activity */
  app: AppMetadata;
  /** Browser-specific data */
  browser?: BrowserMetadata;
  /** Video-specific data */
  video?: VideoMetadata;
  /** IDE-specific data */
  ide?: IdeMetadata;
  /** Terminal-specific data */
  terminal?: TerminalMetadata;
  /** Communication app data */
  communication?: CommunicationMetadata;
  /** Document/productivity data */
  document?: DocumentMetadata;
  /** Brief description of what's happening in this layer */
  activity: string;
  /** Detailed summary of this layer's content */
  summary: string;
  /** Tags for searchability */
  tags: string[];
}

/**
 * Activity analysis entry for a single screenshot
 */
export interface ActivityEntry {
  /** Screenshot filename (e.g., 20260102_171815225.jpg) */
  filename: string;
  /** Parsed timestamp from filename */
  timestamp: number;
  /** ISO date string */
  date: string;
  /** Human-readable time */
  time: string;

  /** Application metadata */
  app: AppMetadata;

  /** Browser-specific data (if app is a browser) */
  browser?: BrowserMetadata;
  /** Video-specific data (if watching video) */
  video?: VideoMetadata;
  /** IDE-specific data (if using code editor) */
  ide?: IdeMetadata;
  /** Terminal-specific data (if using terminal) */
  terminal?: TerminalMetadata;
  /** Communication app data (if using chat/email) */
  communication?: CommunicationMetadata;
  /** Document/productivity data */
  document?: DocumentMetadata;

  /** Multi-activity layers (new format). Each activity represents a separate UI layer. */
  activities?: Activity[];

  /** Brief description of what's happening */
  activity: string;
  /** Detailed analysis of the content */
  details: string;
  /** Free-form narrative summary describing everything visible on screen */
  summary: string;
  /** Tags for searchability */
  tags: string[];
  /** Whether this is a continuation of the previous activity */
  isContinuation: boolean;

  // Legacy fields for compatibility
  /** @deprecated Use app.name */
  application: string;
  /** @deprecated Use browser.url */
  url?: string;
}

/**
 * Activity session - a logical grouping of related activity entries
 */
export interface ActivitySession {
  /** Session ID (first screenshot timestamp) */
  id: string;
  /** Start timestamp */
  startTime: number;
  /** End timestamp */
  endTime: number;
  /** Primary application used in this session */
  primaryApplication: string;
  /** Summary of the session */
  summary: string;
  /** All entries in this session */
  entries: ActivityEntry[];
  /** Tags aggregated from entries */
  tags: string[];
}

/**
 * The full activity context maintained by the agent
 */
export interface ActivityContext {
  /** All processed entries */
  entries: ActivityEntry[];
  /** Sessions (grouped entries) */
  sessions: ActivitySession[];
  /** Last processed filename */
  lastProcessed?: string;
  /** Running summary of recent activity */
  recentSummary: string;
}

/**
 * Screenshot info parsed from filename
 */
export interface ScreenshotInfo {
  filename: string;
  timestamp: number;
  date: string;
  time: string;
  path: string;
}
