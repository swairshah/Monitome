import Foundation

/// Manages screenshot analysis using the Python/BAML service
actor AnalysisManager {
    static let shared = AnalysisManager()

    private let client = AnalysisClient.shared
    private var isProcessing = false

    // MARK: - Process Unprocessed Screenshots

    /// Process all unprocessed screenshots and return activities
    func processUnprocessed() async throws -> [AnalysisClient.ScreenActivity] {
        guard !isProcessing else { return [] }
        isProcessing = true
        defer { isProcessing = false }

        let screenshots = StorageManager.shared.fetchUnprocessed()
        guard !screenshots.isEmpty else { return [] }

        // Check if service is running
        guard await client.healthCheck() else {
            throw AnalysisError.serviceNotRunning
        }

        var activities: [AnalysisClient.ScreenActivity] = []
        var processedIds: [Int64] = []

        for screenshot in screenshots {
            do {
                // Use file path directly - more efficient than loading into memory
                let activity = try await client.analyzeFile(
                    path: screenshot.filePath,
                    timestamp: screenshot.capturedDate
                )
                activities.append(activity)
                if let id = screenshot.id {
                    processedIds.append(id)
                }
            } catch {
                print("Failed to process screenshot \(screenshot.id ?? 0): \(error)")
            }
        }

        // Mark as processed
        if !processedIds.isEmpty {
            StorageManager.shared.markProcessed(ids: processedIds)
        }

        return activities
    }

    /// Process a single screenshot by path
    func processScreenshot(path: String, timestamp: Date) async throws -> AnalysisClient.ScreenActivity {
        return try await client.analyzeFile(path: path, timestamp: timestamp)
    }

    /// Quick extract from a screenshot path
    func quickExtract(path: String) async throws -> AnalysisClient.AppContext {
        let imageData = try Data(contentsOf: URL(fileURLWithPath: path))
        return try await client.quickExtract(imageData: imageData)
    }

    // MARK: - Summarization

    /// Summarize activities from a time period
    func summarize(from: Date, to: Date) async throws -> AnalysisClient.ActivitySummary {
        let screenshots = StorageManager.shared.fetchByDateRange(from: from, to: to)

        guard await client.healthCheck() else {
            throw AnalysisError.serviceNotRunning
        }

        // Process each screenshot
        var activities: [AnalysisClient.ScreenActivity] = []
        for screenshot in screenshots {
            do {
                let activity = try await client.analyzeFile(
                    path: screenshot.filePath,
                    timestamp: screenshot.capturedDate
                )
                activities.append(activity)
            } catch {
                print("Failed to process screenshot for summary: \(error)")
            }
        }

        guard !activities.isEmpty else {
            throw AnalysisManagerError.noActivitiesToSummarize
        }

        return try await client.summarize(activities)
    }

    /// Summarize today's activities
    func summarizeToday() async throws -> AnalysisClient.ActivitySummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return try await summarize(from: startOfDay, to: Date())
    }

    /// Get a daily summary
    func summarizeDay(_ date: Date) async throws -> AnalysisClient.ActivitySummary {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return try await summarize(from: startOfDay, to: endOfDay)
    }

    /// Check if the analysis service is available
    func isServiceAvailable() async -> Bool {
        await client.healthCheck()
    }
}

enum AnalysisManagerError: Error, LocalizedError {
    case noActivitiesToSummarize

    var errorDescription: String? {
        switch self {
        case .noActivitiesToSummarize:
            return "No activities to summarize"
        }
    }
}
