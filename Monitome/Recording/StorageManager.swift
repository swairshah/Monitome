//
//  StorageManager.swift
//  Monitome
//

import Foundation
import GRDB

// MARK: - Screenshot Model

// MARK: - Trigger Reason

enum TriggerReason: String, Sendable {
    case timer = "timer"
    case appSwitch = "app_switch"
    case tabChange = "tab_change"
    case manual = "manual"
}

// MARK: - Screenshot Model

struct Screenshot: Sendable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var capturedAt: Int  // Unix timestamp
    var filePath: String
    var fileSize: Int?
    var isProcessed: Bool
    var triggerReason: String  // timer, app_switch, tab_change, manual

    static let databaseTableName = "screenshots"

    // Map Swift property names to database column names
    enum Columns: String, ColumnExpression {
        case id
        case capturedAt = "captured_at"
        case filePath = "file_path"
        case fileSize = "file_size"
        case isProcessed = "is_processed"
        case triggerReason = "trigger_reason"
    }

    // Custom encoding for database writes
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["captured_at"] = capturedAt
        container["file_path"] = filePath
        container["file_size"] = fileSize
        container["is_processed"] = isProcessed ? 1 : 0
        container["trigger_reason"] = triggerReason
    }

    // Custom decoding for database reads
    init(row: Row) {
        id = row["id"]
        capturedAt = row["captured_at"]
        filePath = row["file_path"]
        fileSize = row["file_size"]
        isProcessed = (row["is_processed"] as Int?) == 1
        triggerReason = row["trigger_reason"] ?? "timer"
    }

    init(id: Int64? = nil, capturedAt: Date, filePath: String, fileSize: Int? = nil, isProcessed: Bool = false, triggerReason: TriggerReason = .timer) {
        self.id = id
        self.capturedAt = Int(capturedAt.timeIntervalSince1970)
        self.filePath = filePath
        self.fileSize = fileSize
        self.isProcessed = isProcessed
        self.triggerReason = triggerReason.rawValue
    }

    var capturedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(capturedAt))
    }

    var trigger: TriggerReason {
        TriggerReason(rawValue: triggerReason) ?? .timer
    }
}

// MARK: - Storage Manager

final class StorageManager: @unchecked Sendable {
    static let shared = StorageManager()

    private var db: DatabasePool!
    private let fileManager = FileManager.default
    private let root: URL

    var recordingsRoot: URL { root }

    // Storage limit in bytes (default 5GB)
    var storageLimitBytes: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: "storageLimitGB")) * 1_073_741_824 }
        set { UserDefaults.standard.set(Int(newValue / 1_073_741_824), forKey: "storageLimitGB") }
    }

    private init() {
        // Set default storage limit if not set
        if UserDefaults.standard.integer(forKey: "storageLimitGB") == 0 {
            UserDefaults.standard.set(5, forKey: "storageLimitGB")
        }

        // Setup directories
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = appSupport.appendingPathComponent("Monitome", isDirectory: true)
        let recordingsDir = baseDir.appendingPathComponent("recordings", isDirectory: true)

        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        root = recordingsDir
        let dbURL = baseDir.appendingPathComponent("monitome.sqlite")

        // Configure database with WAL mode
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA busy_timeout = 5000")
        }

        do {
            db = try DatabasePool(path: dbURL.path, configuration: config)
            migrate()
            startPurgeScheduler()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    // MARK: - Migration

    private func migrate() {
        try? db.write { db in
            // Create table if not exists
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS screenshots (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    captured_at INTEGER NOT NULL,
                    file_path TEXT NOT NULL,
                    file_size INTEGER,
                    is_processed INTEGER DEFAULT 0,
                    trigger_reason TEXT DEFAULT 'timer'
                );
                CREATE INDEX IF NOT EXISTS idx_screenshots_captured_at ON screenshots(captured_at);
                CREATE INDEX IF NOT EXISTS idx_screenshots_processed ON screenshots(is_processed);
                CREATE INDEX IF NOT EXISTS idx_screenshots_trigger ON screenshots(trigger_reason);
            """)

            // Migration: Add trigger_reason column if it doesn't exist
            let columns = try db.columns(in: "screenshots").map { $0.name }
            if !columns.contains("trigger_reason") {
                try db.execute(sql: "ALTER TABLE screenshots ADD COLUMN trigger_reason TEXT DEFAULT 'timer'")
                print("Added trigger_reason column to screenshots table")
            }
        }
    }

    // MARK: - Screenshot URL

    func nextScreenshotURL() -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmssSSS"
        return root.appendingPathComponent("\(df.string(from: Date())).jpg")
    }

    // MARK: - Save Screenshot

    @discardableResult
    func saveScreenshot(url: URL, capturedAt: Date, reason: TriggerReason = .timer) -> Int64? {
        let fileSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        var screenshot = Screenshot(
            capturedAt: capturedAt,
            filePath: url.path,
            fileSize: fileSize,
            isProcessed: false,
            triggerReason: reason
        )

        do {
            try db.write { db in
                try screenshot.insert(db)
            }
            return screenshot.id
        } catch {
            print("Failed to save screenshot: \(error)")
            return nil
        }
    }

    // MARK: - Fetch Screenshots

    func fetchUnprocessed() -> [Screenshot] {
        (try? db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.isProcessed == false)
                .order(Screenshot.Columns.capturedAt.asc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchByDateRange(from: Date, to: Date) -> [Screenshot] {
        let fromTs = Int(from.timeIntervalSince1970)
        let toTs = Int(to.timeIntervalSince1970)

        return (try? db.read { db in
            try Screenshot
                .filter(Screenshot.Columns.capturedAt >= fromTs && Screenshot.Columns.capturedAt <= toTs)
                .order(Screenshot.Columns.capturedAt.desc)
                .fetchAll(db)
        }) ?? []
    }

    func fetchRecent(limit: Int = 100) -> [Screenshot] {
        (try? db.read { db in
            try Screenshot
                .order(Screenshot.Columns.capturedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }) ?? []
    }

    func fetchForDay(_ date: Date) -> [Screenshot] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return fetchByDateRange(from: startOfDay, to: endOfDay)
    }

    // MARK: - Mark as Processed

    func markProcessed(ids: [Int64]) {
        try? db.write { db in
            try db.execute(
                sql: "UPDATE screenshots SET is_processed = 1 WHERE id IN (\(ids.map { String($0) }.joined(separator: ",")))"
            )
        }
    }

    // MARK: - Storage Stats

    func totalStorageUsed() -> Int64 {
        (try? db.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(file_size), 0) FROM screenshots")
        }) ?? 0
    }

    func screenshotCount() -> Int {
        (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshots")
        }) ?? 0
    }

    func todayCount() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let ts = Int(startOfDay.timeIntervalSince1970)
        return (try? db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM screenshots WHERE captured_at >= ?", arguments: [ts])
        }) ?? 0
    }

    // MARK: - Purge Old Screenshots

    private func startPurgeScheduler() {
        // Purge immediately, then every hour
        purgeIfNeeded()
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.purgeIfNeeded()
        }
    }

    func purgeIfNeeded() {
        let limit = storageLimitBytes
        guard limit > 0 else { return }

        var currentSize = totalStorageUsed()
        guard currentSize > limit else { return }

        // Delete oldest screenshots until under limit
        let targetSize = Int64(Double(limit) * 0.9) // Target 90% of limit

        while currentSize > targetSize {
            guard let oldest = try? db.read({ db in
                try Screenshot
                    .order(Screenshot.Columns.capturedAt.asc)
                    .limit(100)
                    .fetchAll(db)
            }), !oldest.isEmpty else { break }

            for screenshot in oldest {
                // Delete file
                try? fileManager.removeItem(atPath: screenshot.filePath)

                // Delete from database
                _ = try? db.write { db in
                    try Screenshot.deleteOne(db, id: screenshot.id)
                }

                currentSize -= Int64(screenshot.fileSize ?? 0)
                if currentSize <= targetSize { break }
            }
        }

        print("Purged screenshots. Storage now: \(currentSize / 1_048_576)MB")
    }

    // MARK: - Delete Screenshot

    func delete(id: Int64) {
        guard let screenshot = try? db.read({ db in
            try Screenshot.fetchOne(db, id: id)
        }) else { return }

        try? fileManager.removeItem(atPath: screenshot.filePath)
        _ = try? db.write { db in
            try Screenshot.deleteOne(db, id: id)
        }
    }
}
