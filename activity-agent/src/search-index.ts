import { existsSync, mkdirSync, unlinkSync } from "fs";
import { dirname } from "path";
import type { ActivityEntry } from "./types.js";

declare global {
  var Bun: any;
}

// Detect if we're running in Bun
const isBun = typeof globalThis.Bun !== "undefined";

/**
 * Get the SQLite Database constructor
 */
async function getSqliteDatabase(): Promise<any> {
  if (isBun) {
    // @ts-ignore - Bun built-in
    const mod = await import("bun:sqlite");
    return mod.Database;
  } else {
    const mod = await import("better-sqlite3");
    return mod.default;
  }
}

/**
 * SQLite FTS5 search index for activity entries
 */
export class SearchIndex {
  private db: any;
  private static DatabaseClass: any = null;

  private constructor(db: any) {
    this.db = db;
  }

  /**
   * Create a new SearchIndex (async factory)
   */
  static async create(dbPath: string): Promise<SearchIndex> {
    const dir = dirname(dbPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    if (!SearchIndex.DatabaseClass) {
      SearchIndex.DatabaseClass = await getSqliteDatabase();
    }

    // Helper to configure db
    const configureDb = (db: any) => {
      db.exec("PRAGMA journal_mode = WAL");
      db.exec("PRAGMA busy_timeout = 10000");
      db.exec("PRAGMA synchronous = NORMAL");
    };

    let db;
    try {
      db = new SearchIndex.DatabaseClass(dbPath);
      configureDb(db);
    } catch (e) {
      // If open fails (e.g., WAL recovery needed), try to recover
      console.error("SQLite open failed, attempting recovery:", e);
      
      // Remove stale WAL/SHM files
      try { unlinkSync(dbPath + "-wal"); } catch {}
      try { unlinkSync(dbPath + "-shm"); } catch {}
      
      // Retry
      db = new SearchIndex.DatabaseClass(dbPath);
      configureDb(db);
    }
    
    const index = new SearchIndex(db);
    index.initialize();
    return index;
  }

  /**
   * Create synchronously (requires DatabaseClass to be pre-loaded)
   */
  static createSync(dbPath: string): SearchIndex {
    const dir = dirname(dbPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    if (!SearchIndex.DatabaseClass) {
      // Fallback: try synchronous require for better-sqlite3
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      SearchIndex.DatabaseClass = require("better-sqlite3");
    }

    const db = new SearchIndex.DatabaseClass(dbPath);
    
    // Enable WAL mode and set busy timeout for concurrent access
    db.exec("PRAGMA journal_mode = WAL");
    db.exec("PRAGMA busy_timeout = 5000");
    
    const index = new SearchIndex(db);
    index.initialize();
    return index;
  }

  /**
   * Pre-load the database class (call once at startup)
   */
  static async preload(): Promise<void> {
    if (!SearchIndex.DatabaseClass) {
      SearchIndex.DatabaseClass = await getSqliteDatabase();
    }
  }

  /**
   * Initialize database tables
   */
  private initialize(): void {
    // Main entries table
    this.exec(`
      CREATE TABLE IF NOT EXISTS entries (
        filename TEXT PRIMARY KEY,
        timestamp INTEGER NOT NULL,
        date TEXT NOT NULL,
        time TEXT NOT NULL,
        app_name TEXT,
        app_category TEXT,
        window_title TEXT,
        url TEXT,
        domain TEXT,
        page_title TEXT,
        page_type TEXT,
        video_platform TEXT,
        video_title TEXT,
        video_channel TEXT,
        ide_name TEXT,
        current_file TEXT,
        file_path TEXT,
        language TEXT,
        project_name TEXT,
        git_branch TEXT,
        terminal_cwd TEXT,
        last_command TEXT,
        communication_app TEXT,
        communication_channel TEXT,
        communication_recipient TEXT,
        document_app TEXT,
        document_title TEXT,
        activity TEXT,
        summary TEXT,
        details TEXT,
        tags TEXT,
        is_continuation INTEGER,
        raw_json TEXT
      )
    `);

    // FTS5 virtual table for full-text search
    this.exec(`
      CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(
        filename,
        app_name,
        window_title,
        url,
        domain,
        page_title,
        video_title,
        video_channel,
        current_file,
        file_path,
        project_name,
        last_command,
        communication_channel,
        communication_recipient,
        document_title,
        activity,
        summary,
        details,
        tags,
        content='entries',
        content_rowid='rowid'
      )
    `);

    // Triggers to keep FTS index in sync
    this.exec(`
      CREATE TRIGGER IF NOT EXISTS entries_ai AFTER INSERT ON entries BEGIN
        INSERT INTO entries_fts(
          rowid, filename, app_name, window_title, url, domain, page_title,
          video_title, video_channel, current_file, file_path, project_name,
          last_command, communication_channel, communication_recipient,
          document_title, activity, summary, details, tags
        ) VALUES (
          NEW.rowid, NEW.filename, NEW.app_name, NEW.window_title, NEW.url,
          NEW.domain, NEW.page_title, NEW.video_title, NEW.video_channel,
          NEW.current_file, NEW.file_path, NEW.project_name, NEW.last_command,
          NEW.communication_channel, NEW.communication_recipient,
          NEW.document_title, NEW.activity, NEW.summary, NEW.details, NEW.tags
        );
      END
    `);

    this.exec(`
      CREATE TRIGGER IF NOT EXISTS entries_ad AFTER DELETE ON entries BEGIN
        INSERT INTO entries_fts(
          entries_fts, rowid, filename, app_name, window_title, url, domain,
          page_title, video_title, video_channel, current_file, file_path,
          project_name, last_command, communication_channel,
          communication_recipient, document_title, activity, summary, details, tags
        ) VALUES (
          'delete', OLD.rowid, OLD.filename, OLD.app_name, OLD.window_title,
          OLD.url, OLD.domain, OLD.page_title, OLD.video_title, OLD.video_channel,
          OLD.current_file, OLD.file_path, OLD.project_name, OLD.last_command,
          OLD.communication_channel, OLD.communication_recipient,
          OLD.document_title, OLD.activity, OLD.summary, OLD.details, OLD.tags
        );
      END
    `);

    this.exec(`
      CREATE TRIGGER IF NOT EXISTS entries_au AFTER UPDATE ON entries BEGIN
        INSERT INTO entries_fts(
          entries_fts, rowid, filename, app_name, window_title, url, domain,
          page_title, video_title, video_channel, current_file, file_path,
          project_name, last_command, communication_channel,
          communication_recipient, document_title, activity, summary, details, tags
        ) VALUES (
          'delete', OLD.rowid, OLD.filename, OLD.app_name, OLD.window_title,
          OLD.url, OLD.domain, OLD.page_title, OLD.video_title, OLD.video_channel,
          OLD.current_file, OLD.file_path, OLD.project_name, OLD.last_command,
          OLD.communication_channel, OLD.communication_recipient,
          OLD.document_title, OLD.activity, OLD.summary, OLD.details, OLD.tags
        );
        INSERT INTO entries_fts(
          rowid, filename, app_name, window_title, url, domain, page_title,
          video_title, video_channel, current_file, file_path, project_name,
          last_command, communication_channel, communication_recipient,
          document_title, activity, summary, details, tags
        ) VALUES (
          NEW.rowid, NEW.filename, NEW.app_name, NEW.window_title, NEW.url,
          NEW.domain, NEW.page_title, NEW.video_title, NEW.video_channel,
          NEW.current_file, NEW.file_path, NEW.project_name, NEW.last_command,
          NEW.communication_channel, NEW.communication_recipient,
          NEW.document_title, NEW.activity, NEW.summary, NEW.details, NEW.tags
        );
      END
    `);

    // Index on timestamp for date queries
    this.exec(`CREATE INDEX IF NOT EXISTS idx_entries_timestamp ON entries(timestamp)`);
    this.exec(`CREATE INDEX IF NOT EXISTS idx_entries_date ON entries(date)`);
    this.exec(`CREATE INDEX IF NOT EXISTS idx_entries_app ON entries(app_name)`);
  }

  /**
   * Execute SQL
   */
  private exec(sql: string): void {
    this.db.exec(sql);
  }

  /**
   * Prepare and run a statement
   */
  private run(sql: string, ...params: any[]): void {
    const stmt = this.db.prepare(sql);
    stmt.run(...params);
  }

  /**
   * Prepare and get all results
   */
  private all(sql: string, ...params: any[]): any[] {
    const stmt = this.db.prepare(sql);
    return stmt.all(...params);
  }

  /**
   * Prepare and get single result
   */
  private get(sql: string, ...params: any[]): any {
    const stmt = this.db.prepare(sql);
    return stmt.get(...params);
  }

  /**
   * Index a single activity entry
   */
  indexEntry(entry: ActivityEntry): void {
    this.run(
      `
      INSERT OR REPLACE INTO entries (
        filename, timestamp, date, time,
        app_name, app_category, window_title,
        url, domain, page_title, page_type,
        video_platform, video_title, video_channel,
        ide_name, current_file, file_path, language, project_name, git_branch,
        terminal_cwd, last_command,
        communication_app, communication_channel, communication_recipient,
        document_app, document_title,
        activity, summary, details, tags, is_continuation, raw_json
      ) VALUES (
        ?, ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?, ?,
        ?, ?, ?,
        ?, ?, ?, ?, ?, ?,
        ?, ?,
        ?, ?, ?,
        ?, ?,
        ?, ?, ?, ?, ?, ?
      )
    `,
      entry.filename,
      entry.timestamp,
      entry.date,
      entry.time,
      entry.app?.name || entry.application,
      entry.app?.category,
      entry.app?.windowTitle,
      entry.browser?.url || entry.url,
      entry.browser?.domain,
      entry.browser?.pageTitle,
      entry.browser?.pageType,
      entry.video?.platform,
      entry.video?.title,
      entry.video?.channel,
      entry.ide?.ide,
      entry.ide?.currentFile,
      entry.ide?.filePath,
      entry.ide?.language,
      entry.ide?.projectName,
      entry.ide?.gitBranch,
      entry.terminal?.cwd,
      entry.terminal?.lastCommand,
      entry.communication?.app,
      entry.communication?.channel,
      entry.communication?.recipient,
      entry.document?.app,
      entry.document?.documentTitle,
      entry.activity,
      entry.summary,
      entry.details,
      entry.tags?.join(", "),
      entry.isContinuation ? 1 : 0,
      JSON.stringify(entry)
    );
  }

  /**
   * Index multiple entries in a transaction
   */
  indexEntries(entries: ActivityEntry[]): void {
    if (isBun) {
      this.db.exec("BEGIN TRANSACTION");
      try {
        for (const entry of entries) {
          this.indexEntry(entry);
        }
        this.db.exec("COMMIT");
      } catch (e) {
        this.db.exec("ROLLBACK");
        throw e;
      }
    } else {
      const transaction = this.db.transaction((items: ActivityEntry[]) => {
        for (const entry of items) {
          this.indexEntry(entry);
        }
      });
      transaction(entries);
    }
  }

  /**
   * Full-text search using FTS5
   */
  search(query: string, limit = 50): ActivityEntry[] {
    // Escape special FTS5 characters and prepare query
    const searchTerms = query
      .replace(/['"]/g, "")
      .split(/\s+/)
      .filter((t) => t.length > 0)
      .map((t) => `"${t}"*`)
      .join(" OR ");

    if (!searchTerms) return [];

    const rows = this.all(
      `
      SELECT e.raw_json, bm25(entries_fts) as rank
      FROM entries_fts fts
      JOIN entries e ON e.rowid = fts.rowid
      WHERE entries_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    `,
      searchTerms,
      limit
    );

    return rows.map((row: { raw_json: string }) => JSON.parse(row.raw_json));
  }

  /**
   * Search with specific field weighting
   */
  searchWeighted(query: string, limit = 50): ActivityEntry[] {
    const searchTerms = query
      .replace(/['"]/g, "")
      .split(/\s+/)
      .filter((t) => t.length > 0)
      .map((t) => `"${t}"*`)
      .join(" OR ");

    if (!searchTerms) return [];

    // Weight: activity and summary highest, then titles, then other fields
    const rows = this.all(
      `
      SELECT e.raw_json,
        bm25(entries_fts, 0, 2, 2, 3, 2, 3, 3, 2, 1, 1, 2, 1, 1, 1, 2, 5, 4, 2, 1) as rank
      FROM entries_fts fts
      JOIN entries e ON e.rowid = fts.rowid
      WHERE entries_fts MATCH ?
      ORDER BY rank
      LIMIT ?
    `,
      searchTerms,
      limit
    );

    return rows.map((row: { raw_json: string }) => JSON.parse(row.raw_json));
  }

  /**
   * Get entries by date
   */
  getByDate(date: string): ActivityEntry[] {
    const rows = this.all(`SELECT raw_json FROM entries WHERE date = ? ORDER BY timestamp`, date);
    return rows.map((row: { raw_json: string }) => JSON.parse(row.raw_json));
  }

  /**
   * Get entries by date range
   */
  getByDateRange(startDate: string, endDate: string): ActivityEntry[] {
    const rows = this.all(
      `
      SELECT raw_json FROM entries
      WHERE date >= ? AND date <= ?
      ORDER BY timestamp
    `,
      startDate,
      endDate
    );
    return rows.map((row: { raw_json: string }) => JSON.parse(row.raw_json));
  }

  /**
   * Get entries by app
   */
  getByApp(appName: string): ActivityEntry[] {
    const rows = this.all(
      `
      SELECT raw_json FROM entries
      WHERE app_name = ?
      ORDER BY timestamp DESC
    `,
      appName
    );
    return rows.map((row: { raw_json: string }) => JSON.parse(row.raw_json));
  }

  /**
   * Get all unique app names
   */
  getApps(): string[] {
    const rows = this.all(`SELECT DISTINCT app_name FROM entries WHERE app_name IS NOT NULL ORDER BY app_name`);
    return rows.map((row: { app_name: string }) => row.app_name);
  }

  /**
   * Get all unique dates
   */
  getDates(): string[] {
    const rows = this.all(`SELECT DISTINCT date FROM entries ORDER BY date DESC`);
    return rows.map((row: { date: string }) => row.date);
  }

  /**
   * Get entry count
   */
  getCount(): number {
    const row = this.get(`SELECT COUNT(*) as count FROM entries`);
    return row.count;
  }

  /**
   * Check if entry exists
   */
  hasEntry(filename: string): boolean {
    return this.get(`SELECT 1 FROM entries WHERE filename = ?`, filename) !== undefined;
  }

  /**
   * Delete an entry
   */
  deleteEntry(filename: string): void {
    this.run(`DELETE FROM entries WHERE filename = ?`, filename);
  }

  /**
   * Clear all entries
   */
  clear(): void {
    this.exec(`DELETE FROM entries`);
  }

  /**
   * Close the database
   */
  close(): void {
    this.db.close();
  }

  /**
   * Rebuild the FTS index (useful after bulk operations)
   */
  rebuildIndex(): void {
    this.exec(`INSERT INTO entries_fts(entries_fts) VALUES('rebuild')`);
  }

  /**
   * Get database stats
   */
  getStats(): { entries: number; apps: number; dates: number; dbSizeBytes: number } {
    const entries = this.getCount();
    const apps = this.getApps().length;
    const dates = this.getDates().length;

    let dbSizeBytes = 0;
    try {
      const sizeRow = this.get(`SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()`);
      dbSizeBytes = sizeRow?.size || 0;
    } catch {
      // Some SQLite versions don't support this
    }

    return {
      entries,
      apps,
      dates,
      dbSizeBytes,
    };
  }
}
