//
//  ActivityAgentManager.swift
//  Monitome
//
//  Manages the activity-agent for indexing screenshots and searching.
//

import Foundation

// MARK: - Search Result

struct ActivitySearchResult: Identifiable {
    let id = UUID()
    let filename: String
    let timestamp: Date
    let activity: String
    let summary: String
    let tags: [String]
    let appName: String?
    let url: String?
    let filePath: String
    
    /// The screenshot from StorageManager, if found
    var screenshot: Screenshot?
}

// MARK: - Activity Log Entry

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType
    
    enum LogType {
        case info
        case success
        case error
        case processing
    }
}

// MARK: - Activity Agent Manager

@MainActor
final class ActivityAgentManager: ObservableObject {
    static let shared = ActivityAgentManager()
    
    /// Path to the activity-agent binary
    private let agentPath: String
    
    /// Data directory (Application Support/Monitome)
    private let dataDir: String
    
    /// Timer for periodic indexing
    private var indexTimer: Timer?
    
    /// Whether indexing is currently running
    @Published var isIndexing = false
    
    /// Last index time
    @Published var lastIndexTime: Date?
    
    /// Number of indexed entries
    @Published var indexedCount: Int = 0
    
    /// Activity log entries
    @Published var logEntries: [ActivityLogEntry] = []
    
    /// Maximum log entries to keep
    private let maxLogEntries = 100
    
    /// Whether the agent binary exists
    var isAgentAvailable: Bool {
        FileManager.default.fileExists(atPath: agentPath)
    }
    
    private init() {
        // Look for activity-agent in common locations
        let bundleMacOS = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/activity-agent").path
        let bundleResources = Bundle.main.resourcePath.map { $0 + "/activity-agent" } ?? ""
        
        let possiblePaths = [
            // In the app bundle's MacOS folder (preferred for executables)
            bundleMacOS,
            // In the app bundle's Resources
            bundleResources,
            // Development: source project
            NSHomeDirectory() + "/work/projects/Monitome/activity-agent/dist/activity-agent",
            // Installed via brew or manually
            "/usr/local/bin/activity-agent",
            "/opt/homebrew/bin/activity-agent",
            NSHomeDirectory() + "/.local/bin/activity-agent"
        ]
        
        let foundPath = possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
        self.agentPath = foundPath ?? "/usr/local/bin/activity-agent"
        
        if let foundPath = foundPath {
            print("Activity agent found at: \(foundPath)")
        } else {
            print("Activity agent NOT found. Searched paths:")
            for path in possiblePaths {
                print("  - \(path)")
            }
        }
        
        // Data directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.dataDir = appSupport.appendingPathComponent("Monitome").path
        
        // Load initial stats
        Task {
            await refreshStats()
        }
    }
    
    // MARK: - Indexing
    
    /// Start periodic indexing (every 60 seconds)
    func startPeriodicIndexing() {
        guard isAgentAvailable else {
            log("Activity agent not found at \(agentPath)", type: .error)
            return
        }
        
        // Check if indexing is enabled
        guard UserDefaults.standard.bool(forKey: "indexingEnabled") != false else {
            log("Indexing disabled in settings", type: .info)
            return
        }
        
        // Index immediately
        Task {
            await indexNewScreenshots()
        }
        
        // Then every 60 seconds
        indexTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Check if still enabled
                guard UserDefaults.standard.bool(forKey: "indexingEnabled") != false else { return }
                await self?.indexNewScreenshots()
            }
        }
    }
    
    /// Stop periodic indexing
    func stopPeriodicIndexing() {
        indexTimer?.invalidate()
        indexTimer = nil
        log("Periodic indexing stopped", type: .info)
    }
    
    /// Reindex all screenshots from scratch
    func reindexAll() async {
        guard !isIndexing, isAgentAvailable else { return }
        
        isIndexing = true
        log("Starting full reindex...", type: .info)
        
        defer { isIndexing = false }
        
        do {
            // First rebuild the index
            let rebuildOutput = try await runAgent(["rebuild"])
            log("Index cleared", type: .info)
            
            // Then process all screenshots (in batches)
            var totalProcessed = 0
            var hasMore = true
            
            while hasMore {
                let output = try await runAgentWithStreaming(["process", "20"]) { [weak self] line in
                    Task { @MainActor in
                        self?.parseAndLogLine(line)
                    }
                }
                
                // Check if there are more to process
                if output.contains("No new screenshots to process") {
                    hasMore = false
                } else if let match = output.range(of: #"Total entries: (\d+)"#, options: .regularExpression) {
                    let countStr = output[match].replacingOccurrences(of: "Total entries: ", with: "")
                    if let count = Int(countStr) {
                        totalProcessed = count
                    }
                    // Check if we got less than 20, meaning we're done
                    if output.contains("Found 0") || !output.contains("Processing:") {
                        hasMore = false
                    }
                }
            }
            
            log("Full reindex complete. Total: \(totalProcessed) entries", type: .success)
            lastIndexTime = Date()
            await refreshStats()
        } catch {
            log("Reindex failed: \(error.localizedDescription)", type: .error)
        }
    }
    
    /// Clear the index completely
    func clearIndex() async {
        guard isAgentAvailable else { return }
        
        log("Clearing index...", type: .info)
        
        do {
            let _ = try await runAgent(["rebuild"])
            log("Index cleared", type: .success)
            await refreshStats()
        } catch {
            log("Clear failed: \(error.localizedDescription)", type: .error)
        }
    }
    
    /// Add a log entry
    func log(_ message: String, type: ActivityLogEntry.LogType = .info) {
        let entry = ActivityLogEntry(timestamp: Date(), message: message, type: type)
        logEntries.append(entry)
        
        // Trim old entries
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }
    
    /// Clear the log
    func clearLog() {
        logEntries.removeAll()
    }
    
    /// Index new screenshots (calls activity-agent process)
    func indexNewScreenshots() async {
        guard !isIndexing, isAgentAvailable else { return }
        
        isIndexing = true
        log("Starting indexing...", type: .info)
        
        defer { 
            isIndexing = false
        }
        
        do {
            let output = try await runAgentWithStreaming(["process", "10"]) { [weak self] line in
                Task { @MainActor in
                    self?.parseAndLogLine(line)
                }
            }
            
            // Parse final stats
            if output.contains("No new screenshots to process") {
                log("No new screenshots to process", type: .info)
            } else if let match = output.range(of: #"Total entries: (\d+)"#, options: .regularExpression) {
                let countStr = output[match].replacingOccurrences(of: "Total entries: ", with: "")
                log("Indexing complete. Total entries: \(countStr)", type: .success)
            }
            
            lastIndexTime = Date()
            await refreshStats()
        } catch {
            log("Indexing failed: \(error.localizedDescription)", type: .error)
        }
    }
    
    /// Parse a line from agent output and log it
    private func parseAndLogLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Processing line: [1/10] Processing: filename.jpg
        if trimmed.contains("Processing:") {
            if let filename = trimmed.components(separatedBy: "Processing: ").last {
                log("Processing: \(filename)", type: .processing)
            }
        }
        // Activity line from output
        else if trimmed.hasPrefix("[") && trimmed.contains("]") {
            // This is a result header like [2025-12-31 14:17:23] Chrome
            log(trimmed, type: .success)
        }
        // Activity description
        else if trimmed.hasPrefix("Activity:") {
            log("  \(trimmed)", type: .info)
        }
    }
    
    /// Refresh index statistics
    func refreshStats() async {
        guard isAgentAvailable else { return }
        
        do {
            let output = try await runAgent(["status"])
            // Parse "Indexed: X entries" from output
            if let match = output.range(of: #"Indexed: (\d+) entries"#, options: .regularExpression) {
                let numberStr = output[match].replacingOccurrences(of: "Indexed: ", with: "").replacingOccurrences(of: " entries", with: "")
                indexedCount = Int(numberStr) ?? 0
            }
        } catch {
            print("Failed to get stats: \(error)")
        }
    }
    
    // MARK: - Search
    
    /// Fast FTS search (direct SQLite, instant)
    func searchFTS(_ query: String) async -> [ActivitySearchResult] {
        guard isAgentAvailable, !query.isEmpty else { return [] }
        
        do {
            let output = try await runAgent(["fts", query])
            return parseSearchResults(output)
        } catch {
            print("FTS search failed: \(error)")
            return []
        }
    }
    
    /// Smart agent search (uses LLM for complex queries)
    func searchSmart(_ query: String) async -> String {
        guard isAgentAvailable, !query.isEmpty else { return "" }
        
        do {
            let output = try await runAgent(["search", query])
            // The search command outputs the agent's answer directly
            return output
        } catch {
            print("Smart search failed: \(error)")
            return "Search failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private Helpers
    
    /// Get environment with API key
    private func getEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        
        // Add API key from UserDefaults if set
        if let apiKey = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !apiKey.isEmpty {
            env["ANTHROPIC_API_KEY"] = apiKey
        }
        
        return env
    }
    
    private func runAgent(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = ["--data", dataDir] + arguments
        process.environment = getEnvironment()
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ActivityAgent",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output]
                    ))
                }
            }
        }
    }
    
    /// Run agent with streaming output
    private func runAgentWithStreaming(_ arguments: [String], onLine: @escaping (String) -> Void) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = ["--data", dataDir] + arguments
        process.environment = getEnvironment()
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var fullOutput = ""
        
        // Set up streaming reader
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                fullOutput += str
                // Split into lines and call handler
                let lines = str.components(separatedBy: "\n")
                for line in lines {
                    onLine(line)
                }
            }
        }
        
        try process.run()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                
                // Clean up handler
                pipe.fileHandleForReading.readabilityHandler = nil
                
                // Read any remaining data
                let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: remainingData, encoding: .utf8), !str.isEmpty {
                    fullOutput += str
                    let lines = str.components(separatedBy: "\n")
                    for line in lines {
                        onLine(line)
                    }
                }
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: fullOutput)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "ActivityAgent",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: fullOutput]
                    ))
                }
            }
        }
    }
    
    private func parseSearchResults(_ output: String) -> [ActivitySearchResult] {
        var results: [ActivitySearchResult] = []
        
        // Parse the FTS output format
        // Expected format from CLI:
        // [2026-01-02 17:18:15] Chrome
        //   File: 20260102_171815225.jpg
        //   Activity: ...
        //   Summary: ...
        //   Tags: ...
        
        let lines = output.components(separatedBy: "\n")
        var currentResult: (date: String, time: String, app: String, activity: String, summary: String, tags: [String], url: String?, filename: String)?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Header line: [2026-01-02 17:18:15] AppName
            if let match = trimmed.range(of: #"\[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\] (.+)"#, options: .regularExpression) {
                // Save previous result if exists
                if let r = currentResult {
                    if let result = createSearchResult(from: r) {
                        results.append(result)
                    }
                }
                
                // Parse new result header
                let fullMatch = String(trimmed[match])
                let parts = fullMatch.replacingOccurrences(of: "[", with: "").components(separatedBy: "] ")
                if parts.count >= 2 {
                    let dateTime = parts[0].components(separatedBy: " ")
                    let app = parts[1].components(separatedBy: " (")[0] // Remove "(continuation)" suffix
                    currentResult = (
                        date: dateTime[0],
                        time: dateTime.count > 1 ? dateTime[1] : "",
                        app: app,
                        activity: "",
                        summary: "",
                        tags: [],
                        url: nil,
                        filename: ""
                    )
                }
            }
            // File line (filename)
            else if trimmed.hasPrefix("File: "), currentResult != nil {
                currentResult?.filename = String(trimmed.dropFirst(6))
            }
            // Activity line
            else if trimmed.hasPrefix("Activity: "), currentResult != nil {
                currentResult?.activity = String(trimmed.dropFirst(10))
            }
            // Summary line
            else if trimmed.hasPrefix("Summary: "), currentResult != nil {
                currentResult?.summary = String(trimmed.dropFirst(9))
            }
            // Tags line
            else if trimmed.hasPrefix("Tags: "), currentResult != nil {
                let tagsStr = String(trimmed.dropFirst(6))
                currentResult?.tags = tagsStr.components(separatedBy: ", ")
            }
            // URL line
            else if trimmed.hasPrefix("URL: "), currentResult != nil {
                currentResult?.url = String(trimmed.dropFirst(5))
            }
        }
        
        // Don't forget the last result
        if let r = currentResult {
            if let result = createSearchResult(from: r) {
                results.append(result)
            }
        }
        
        return results
    }
    
    private func createSearchResult(from r: (date: String, time: String, app: String, activity: String, summary: String, tags: [String], url: String?, filename: String)) -> ActivitySearchResult? {
        // Parse date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let timestamp = dateFormatter.date(from: "\(r.date) \(r.time)") else {
            return nil
        }
        
        let recordingsDir = URL(fileURLWithPath: dataDir).appendingPathComponent("recordings")
        
        // Use the filename from output if available
        let filename: String
        let filePath: String
        
        if !r.filename.isEmpty {
            filename = r.filename
            filePath = recordingsDir.appendingPathComponent(filename).path
        } else {
            // Fallback: construct filename from date/time
            let filenameFormatter = DateFormatter()
            filenameFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let filenamePrefix = filenameFormatter.string(from: timestamp)
            
            // Find the actual file in recordings
            let files = (try? FileManager.default.contentsOfDirectory(atPath: recordingsDir.path)) ?? []
            let matchingFile = files.first { $0.hasPrefix(filenamePrefix) && $0.hasSuffix(".jpg") }
            
            filename = matchingFile ?? "\(filenamePrefix)000.jpg"
            filePath = recordingsDir.appendingPathComponent(filename).path
        }
        
        return ActivitySearchResult(
            filename: filename,
            timestamp: timestamp,
            activity: r.activity,
            summary: r.summary,
            tags: r.tags,
            appName: r.app,
            url: r.url,
            filePath: filePath
        )
    }
}
