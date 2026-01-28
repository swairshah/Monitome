import { readdirSync, existsSync } from "fs";
import { join } from "path";
import type { ScreenshotInfo } from "./types.js";

/**
 * Parse a screenshot filename like 20260102_171815225.jpg
 * Format: YYYYMMDD_HHMMSSmmm.jpg
 */
export function parseScreenshotFilename(filename: string): ScreenshotInfo | null {
  const match = filename.match(/^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(\d{3})\.jpg$/);
  if (!match) return null;

  const [, year, month, day, hour, minute, second, ms] = match;

  const timestamp = new Date(
    parseInt(year),
    parseInt(month) - 1,
    parseInt(day),
    parseInt(hour),
    parseInt(minute),
    parseInt(second),
    parseInt(ms)
  ).getTime();

  return {
    filename,
    timestamp,
    date: `${year}-${month}-${day}`,
    time: `${hour}:${minute}:${second}`,
    path: "", // Will be set when loading
  };
}

/**
 * Get the recordings directory for a data directory.
 * Checks for 'recordings/' subdirectory first, falls back to dataDir itself.
 */
export function getRecordingsDir(dataDir: string): string {
  const recordingsSubdir = join(dataDir, "recordings");
  if (existsSync(recordingsSubdir)) {
    return recordingsSubdir;
  }
  return dataDir;
}

/**
 * List all screenshots in a directory, sorted by timestamp.
 * Automatically checks for 'recordings/' subdirectory.
 */
export function listScreenshots(dataDir: string): ScreenshotInfo[] {
  const recordingsDir = getRecordingsDir(dataDir);
  
  let files: string[];
  try {
    files = readdirSync(recordingsDir);
  } catch {
    return [];
  }

  const screenshots: ScreenshotInfo[] = [];

  for (const file of files) {
    const info = parseScreenshotFilename(file);
    if (info) {
      info.path = join(recordingsDir, file);
      screenshots.push(info);
    }
  }

  return screenshots.sort((a, b) => a.timestamp - b.timestamp);
}

/**
 * Get screenshots after a certain timestamp.
 * Automatically checks for 'recordings/' subdirectory.
 */
export function getScreenshotsAfter(dataDir: string, afterTimestamp?: number): ScreenshotInfo[] {
  const all = listScreenshots(dataDir);
  if (!afterTimestamp) return all;
  return all.filter((s) => s.timestamp > afterTimestamp);
}

/**
 * Group screenshots by date
 */
export function groupScreenshotsByDate(screenshots: ScreenshotInfo[]): Map<string, ScreenshotInfo[]> {
  const groups = new Map<string, ScreenshotInfo[]>();

  for (const screenshot of screenshots) {
    const existing = groups.get(screenshot.date) || [];
    existing.push(screenshot);
    groups.set(screenshot.date, existing);
  }

  return groups;
}
