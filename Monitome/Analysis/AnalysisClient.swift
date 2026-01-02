import Foundation

/// Client for calling the Monitome Analysis Service (Python/BAML)
actor AnalysisClient {
    static let shared = AnalysisClient()

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8420")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared
    }

    // MARK: - Response Types

    struct AppContext: Codable {
        let appName: String
        let windowTitle: String?
        let appCategory: String

        enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case windowTitle = "window_title"
            case appCategory = "app_category"
        }
    }

    struct ScreenActivity: Codable {
        let timestamp: String
        let app: AppContext
        let activityType: String
        let description: String
        let keyContent: [String]
        let urls: [String]

        enum CodingKeys: String, CodingKey {
            case timestamp
            case app
            case activityType = "activity_type"
            case description
            case keyContent = "key_content"
            case urls
        }
    }

    struct AppUsage: Codable {
        let appName: String
        let category: String
        let screenshotCount: Int

        enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case category
            case screenshotCount = "screenshot_count"
        }
    }

    struct ActivitySummary: Codable {
        let timePeriod: String
        let totalScreenshots: Int
        let mainActivities: [String]
        let appsUsed: [AppUsage]
        let productivityScore: Int
        let summary: String

        enum CodingKeys: String, CodingKey {
            case timePeriod = "time_period"
            case totalScreenshots = "total_screenshots"
            case mainActivities = "main_activities"
            case appsUsed = "apps_used"
            case productivityScore = "productivity_score"
            case summary
        }
    }

    // MARK: - Request Types

    private struct AnalyzeRequest: Codable {
        let imageBase64: String
        let timestamp: String

        enum CodingKeys: String, CodingKey {
            case imageBase64 = "image_base64"
            case timestamp
        }
    }

    private struct AnalyzeFileRequest: Codable {
        let filePath: String
        let timestamp: String?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case timestamp
        }
    }

    private struct QuickExtractRequest: Codable {
        let imageBase64: String

        enum CodingKeys: String, CodingKey {
            case imageBase64 = "image_base64"
        }
    }

    private struct SummarizeRequest: Codable {
        let activities: [ScreenActivity]
    }

    // MARK: - API Methods

    /// Analyze a screenshot from image data
    func analyze(imageData: Data, timestamp: Date) async throws -> ScreenActivity {
        let request = AnalyzeRequest(
            imageBase64: imageData.base64EncodedString(),
            timestamp: ISO8601DateFormatter().string(from: timestamp)
        )
        return try await post(endpoint: "analyze", body: request)
    }

    /// Analyze a screenshot from file path (more efficient - no base64 encoding)
    func analyzeFile(path: String, timestamp: Date? = nil) async throws -> ScreenActivity {
        let request = AnalyzeFileRequest(
            filePath: path,
            timestamp: timestamp.map { ISO8601DateFormatter().string(from: $0) }
        )
        return try await post(endpoint: "analyze-file", body: request)
    }

    /// Quick extraction - just get app context
    func quickExtract(imageData: Data) async throws -> AppContext {
        let request = QuickExtractRequest(imageBase64: imageData.base64EncodedString())
        return try await post(endpoint: "quick-extract", body: request)
    }

    /// Summarize multiple activities
    func summarize(_ activities: [ScreenActivity]) async throws -> ActivitySummary {
        let request = SummarizeRequest(activities: activities)
        return try await post(endpoint: "summarize", body: request)
    }

    /// Check if service is running
    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - HTTP

    private func post<Request: Encodable, Response: Decodable>(
        endpoint: String,
        body: Request
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalysisError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }
}

enum AnalysisError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int, message: String)
    case serviceNotRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from analysis service"
        case .serverError(let code, let message):
            return "Analysis service error (\(code)): \(message)"
        case .serviceNotRunning:
            return "Analysis service not running. Start with: cd service && uv run main.py"
        }
    }
}
