//
//  PiAgentManager.swift
//  Monitome
//
//  Manages Pi agent for search and chat functionality.
//  Uses Pi with the monitome-search extension.
//

import Foundation

// MARK: - Pi Agent Manager

@MainActor
final class PiAgentManager: ObservableObject {
    static let shared = PiAgentManager()
    
    /// Path to the pi binary
    private let piPath: String
    
    /// Path to the extension
    private let extensionPath: String
    
    /// Data directory (Application Support/Monitome)
    private let dataDir: URL
    
    /// Session directory for Pi
    private let sessionDir: URL
    
    /// Whether pi binary exists
    var isPiAvailable: Bool {
        FileManager.default.fileExists(atPath: piPath)
    }
    
    /// Whether extension exists  
    var isExtensionAvailable: Bool {
        FileManager.default.fileExists(atPath: extensionPath)
    }
    
    private init() {
        // Data directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.dataDir = appSupport.appendingPathComponent("Monitome")
        self.sessionDir = dataDir.appendingPathComponent("sessions/monitome")
        
        // Create session directory if needed
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        // Look for pi in common locations
        let bundleMacOS = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/pi").path
        let bundleResources = Bundle.main.resourcePath.map { $0 + "/pi" } ?? ""
        
        let possiblePiPaths = [
            bundleMacOS,
            bundleResources,
            // Development paths
            NSHomeDirectory() + "/work/agents/pi-mono/packages/coding-agent/dist/cli.js",
            "/usr/local/bin/pi",
            "/opt/homebrew/bin/pi",
            NSHomeDirectory() + "/.nvm/versions/node/v22.16.0/bin/pi"
        ]
        
        let foundPiPath = possiblePiPaths.first { FileManager.default.fileExists(atPath: $0) }
        self.piPath = foundPiPath ?? "/usr/local/bin/pi"
        
        // Look for extension
        let bundleExtension = Bundle.main.resourcePath.map { $0 + "/extensions/monitome-search/index.js" } ?? ""
        
        let possibleExtPaths = [
            bundleExtension,
            // Development paths
            NSHomeDirectory() + "/work/projects/Monitome/activity-agent/dist/extension/index.js",
        ]
        
        let foundExtPath = possibleExtPaths.first { FileManager.default.fileExists(atPath: $0) }
        self.extensionPath = foundExtPath ?? ""
        
        if let foundPi = foundPiPath {
            print("[PiAgent] Pi found at: \(foundPi)")
        } else {
            print("[PiAgent] Pi NOT found")
        }
        
        if let foundExt = foundExtPath {
            print("[PiAgent] Extension found at: \(foundExt)")
        } else {
            print("[PiAgent] Extension NOT found")
        }
    }
    
    // MARK: - Chat
    
    /// Send a chat message using Pi with the extension
    /// Continues previous session if available
    func chat(_ message: String) async -> String {
        guard isPiAvailable else {
            return "Pi not available. Please check installation."
        }
        
        guard isExtensionAvailable else {
            return "Monitome extension not found."
        }
        
        do {
            return try await runPi(message: message, continueSession: true)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
    
    /// Start a new session (clear history)
    func newSession() async -> String {
        guard isPiAvailable, isExtensionAvailable else {
            return "Pi or extension not available."
        }
        
        do {
            return try await runPi(message: "Hello! I'm ready to help you search your activity.", continueSession: false)
        } catch {
            return "Error starting new session: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private
    
    private func getEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        
        // Add API key from UserDefaults if set
        if let apiKey = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !apiKey.isEmpty {
            env["ANTHROPIC_API_KEY"] = apiKey
        }
        
        // Set data directory for extension
        env["MONITOME_DATA_DIR"] = dataDir.path
        
        return env
    }
    
    private func runPi(message: String, continueSession: Bool) async throws -> String {
        let process = Process()
        
        // Check if piPath is a .js file (development) or binary
        if piPath.hasSuffix(".js") {
            // Run via node
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            var args = ["node", piPath]
            args += buildPiArgs(message: message, continueSession: continueSession)
            process.arguments = args
        } else {
            process.executableURL = URL(fileURLWithPath: piPath)
            process.arguments = buildPiArgs(message: message, continueSession: continueSession)
        }
        
        process.environment = getEnvironment()
        process.currentDirectoryURL = dataDir
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Filter out extension loading messages
                let cleanOutput = output
                    .components(separatedBy: "\n")
                    .filter { !$0.hasPrefix("[monitome]") }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: cleanOutput)
                } else {
                    // Pi might return non-zero for user abort, etc.
                    // Still return the output
                    if !cleanOutput.isEmpty {
                        continuation.resume(returning: cleanOutput)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "PiAgent",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: output]
                        ))
                    }
                }
            }
        }
    }
    
    private func buildPiArgs(message: String, continueSession: Bool) -> [String] {
        var args: [String] = []
        
        // Extension
        args += ["--extension", extensionPath]
        
        // Session management
        args += ["--session-dir", sessionDir.path]
        if continueSession {
            args += ["--continue"]
        }
        
        // Non-interactive mode
        args += ["--print"]
        
        // Model (use haiku for speed/cost)
        args += ["--provider", "anthropic"]
        args += ["--model", "claude-haiku-4-5"]
        
        // Disable built-in tools (we only want our search tools)
        args += ["--no-tools"]
        
        // The message
        args += [message]
        
        return args
    }
}
