//
//  ImageDiff.swift
//  Monitome
//
//  Perceptual hashing for detecting similar screenshots.
//

import CoreGraphics
import CoreImage

// MARK: - Perceptual Hash

/// Generates a perceptual hash (pHash) for an image.
/// Similar images produce similar hashes, allowing fast duplicate detection.
enum PerceptualHash {

    /// Hash size (8x8 = 64 bits fits in UInt64)
    private static let hashSize = 8

    /// Compute perceptual hash for a CGImage
    static func compute(_ image: CGImage) -> UInt64 {
        // 1. Convert to grayscale and resize to hashSize x hashSize
        let grayscalePixels = resizeToGrayscale(image, size: hashSize)

        guard grayscalePixels.count == hashSize * hashSize else {
            return 0
        }

        // 2. Calculate average pixel value
        let sum = grayscalePixels.reduce(0) { $0 + Int($1) }
        let average = sum / grayscalePixels.count

        // 3. Build hash: set bit to 1 if pixel > average, else 0
        var hash: UInt64 = 0
        for (index, pixel) in grayscalePixels.enumerated() {
            if pixel > UInt8(average) {
                hash |= (1 << index)
            }
        }

        return hash
    }

    /// Compute Hamming distance between two hashes (number of differing bits)
    static func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        return (hash1 ^ hash2).nonzeroBitCount
    }

    /// Check if two hashes represent similar images
    /// - Parameter threshold: Maximum allowed Hamming distance (default 5 out of 64 bits ≈ 92% similar)
    static func areSimilar(_ hash1: UInt64, _ hash2: UInt64, threshold: Int = 5) -> Bool {
        return hammingDistance(hash1, hash2) <= threshold
    }

    // MARK: - Private Helpers

    private static func resizeToGrayscale(_ image: CGImage, size: Int) -> [UInt8] {
        // Create grayscale context at target size
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: size * size)

        guard let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return []
        }

        // Draw image scaled to fit (this handles the resize)
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        return pixels
    }
}

// MARK: - Duplicate Detector

/// Tracks recent screenshot hashes to detect duplicates
final class DuplicateDetector {

    /// Singleton instance
    static let shared = DuplicateDetector()

    /// Hamming distance threshold for considering images as duplicates
    /// Lower = stricter matching (fewer false positives, might miss some duplicates)
    /// Higher = looser matching (catches more duplicates, might have false positives)
    /// Default of 5 means images must be ~92% similar (59/64 bits matching)
    var threshold: Int = 5

    /// Last captured screenshot hash (per display to handle multi-monitor)
    private var lastHashes: [CGDirectDisplayID: UInt64] = [:]
    private let lock = NSLock()

    private init() {}

    /// Check if image is a duplicate of the last captured image for this display
    /// - Returns: true if the image should be skipped (is a duplicate)
    func isDuplicate(_ image: CGImage, forDisplay displayID: CGDirectDisplayID) -> Bool {
        let newHash = PerceptualHash.compute(image)

        lock.lock()
        defer { lock.unlock() }

        guard let lastHash = lastHashes[displayID] else {
            // First image for this display, not a duplicate
            lastHashes[displayID] = newHash
            return false
        }

        let isSimilar = PerceptualHash.areSimilar(lastHash, newHash, threshold: threshold)

        if !isSimilar {
            // Different image, update the hash
            lastHashes[displayID] = newHash
        }

        return isSimilar
    }

    /// Force update the hash for a display (call when saving regardless of duplicate status)
    func updateHash(_ image: CGImage, forDisplay displayID: CGDirectDisplayID) {
        let hash = PerceptualHash.compute(image)
        lock.lock()
        lastHashes[displayID] = hash
        lock.unlock()
    }

    /// Clear all stored hashes
    func reset() {
        lock.lock()
        lastHashes.removeAll()
        lock.unlock()
    }
}
