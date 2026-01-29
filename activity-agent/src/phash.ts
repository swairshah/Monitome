import imghash from "imghash";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";

/**
 * Perceptual hash storage and comparison
 * Used to detect similar/duplicate screenshots
 */

export interface PhashEntry {
  filename: string;
  hash: string;
  timestamp: number;
}

export interface PhashIndex {
  version: number;
  entries: PhashEntry[];
}

const PHASH_VERSION = 1;
const HAMMING_THRESHOLD = 25; // Hashes within this distance are considered similar (256 bits total)
const HASH_BITS = 16; // 16 bits = 64 char hex hash

/**
 * Calculate hamming distance between two hex hash strings
 */
function hammingDistance(hash1: string, hash2: string): number {
  if (hash1.length !== hash2.length) return Infinity;
  
  // Convert hex to binary and count differences
  const bin1 = imghash.hexToBinary(hash1);
  const bin2 = imghash.hexToBinary(hash2);
  
  let distance = 0;
  for (let i = 0; i < bin1.length; i++) {
    if (bin1[i] !== bin2[i]) distance++;
  }
  return distance;
}

/**
 * PhashManager - manages perceptual hash index for screenshots
 */
export class PhashManager {
  private indexPath: string;
  private index: PhashIndex;
  private hashMap: Map<string, PhashEntry>; // filename -> entry for quick lookup

  constructor(dataDir: string) {
    this.indexPath = join(dataDir, "phash-index.json");
    this.index = this.loadIndex();
    this.hashMap = new Map(this.index.entries.map(e => [e.filename, e]));
  }

  private loadIndex(): PhashIndex {
    if (existsSync(this.indexPath)) {
      try {
        const data = JSON.parse(readFileSync(this.indexPath, "utf-8"));
        if (data.version === PHASH_VERSION) {
          return data;
        }
      } catch {
        // Ignore corrupt index
      }
    }
    return { version: PHASH_VERSION, entries: [] };
  }

  private saveIndex(): void {
    writeFileSync(this.indexPath, JSON.stringify(this.index, null, 2));
  }

  /**
   * Compute perceptual hash for an image file
   */
  async computeHash(imagePath: string): Promise<string> {
    const hash = await imghash.hash(imagePath, HASH_BITS);
    return hash;
  }

  /**
   * Check if we already have a hash for this filename
   */
  hasHash(filename: string): boolean {
    return this.hashMap.has(filename);
  }

  /**
   * Get hash for a filename
   */
  getHash(filename: string): string | undefined {
    return this.hashMap.get(filename)?.hash;
  }

  /**
   * Find similar screenshots based on perceptual hash
   * Returns filenames of similar images within threshold
   */
  findSimilar(hash: string, excludeFilename?: string): PhashEntry[] {
    const similar: PhashEntry[] = [];
    
    for (const entry of this.index.entries) {
      if (excludeFilename && entry.filename === excludeFilename) continue;
      
      const distance = hammingDistance(hash, entry.hash);
      if (distance <= HAMMING_THRESHOLD) {
        similar.push(entry);
      }
    }
    
    return similar;
  }

  /**
   * Check if image is similar to recent ones, and if not, add it
   * Returns: { isDuplicate: boolean, similarTo?: string, hash: string }
   */
  async checkAndAdd(
    imagePath: string, 
    filename: string, 
    timestamp: number
  ): Promise<{ isDuplicate: boolean; similarTo?: string; hash: string }> {
    // Skip if already indexed
    if (this.hasHash(filename)) {
      return { isDuplicate: false, hash: this.getHash(filename)! };
    }

    let hash: string;
    try {
      hash = await this.computeHash(imagePath);
    } catch (error) {
      // If hashing fails, don't block - just proceed without duplicate detection
      console.error(`Warning: Could not compute hash for ${filename}: ${error}`);
      return { isDuplicate: false, hash: "" };
    }
    
    // Check against recent entries (last 100)
    const recentEntries = this.index.entries.slice(-100);
    for (const entry of recentEntries) {
      const distance = hammingDistance(hash, entry.hash);
      if (distance <= HAMMING_THRESHOLD) {
        // Found similar - still add to index but mark as duplicate
        const newEntry: PhashEntry = { filename, hash, timestamp };
        this.index.entries.push(newEntry);
        this.hashMap.set(filename, newEntry);
        this.saveIndex();
        
        return { isDuplicate: true, similarTo: entry.filename, hash };
      }
    }
    
    // No similar found - add to index
    const entry: PhashEntry = { filename, hash, timestamp };
    this.index.entries.push(entry);
    this.hashMap.set(filename, entry);
    
    // Keep index manageable - remove very old entries (keep last 10000)
    if (this.index.entries.length > 10000) {
      const removed = this.index.entries.shift();
      if (removed) this.hashMap.delete(removed.filename);
    }
    
    this.saveIndex();
    return { isDuplicate: false, hash };
  }

  /**
   * Get stats about the phash index
   */
  getStats(): { totalHashes: number; indexSizeBytes: number } {
    return {
      totalHashes: this.index.entries.length,
      indexSizeBytes: existsSync(this.indexPath) 
        ? readFileSync(this.indexPath).length 
        : 0,
    };
  }
}
