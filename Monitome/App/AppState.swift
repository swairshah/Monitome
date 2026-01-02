//
//  AppState.swift
//  Monitome
//

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private let recordingKey = "isRecording"
    private let eventTriggersKey = "eventTriggersEnabled"

    @Published var isRecording: Bool {
        didSet {
            UserDefaults.standard.set(isRecording, forKey: recordingKey)
            NotificationCenter.default.post(name: .recordingStateChanged, object: nil)
        }
    }

    @Published var eventTriggersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(eventTriggersEnabled, forKey: eventTriggersKey)
            NotificationCenter.default.post(name: .eventTriggersStateChanged, object: nil)
        }
    }

    private init() {
        // Restore saved preferences
        self.isRecording = UserDefaults.standard.bool(forKey: recordingKey)

        // Default event triggers to ON if not set
        if UserDefaults.standard.object(forKey: eventTriggersKey) == nil {
            UserDefaults.standard.set(true, forKey: eventTriggersKey)
        }
        self.eventTriggersEnabled = UserDefaults.standard.bool(forKey: eventTriggersKey)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a screenshot is captured and saved
    static let screenshotCaptured = Notification.Name("screenshotCaptured")

    /// Posted when recording state changes
    static let recordingStateChanged = Notification.Name("recordingStateChanged")

    /// Posted when event triggers setting changes
    static let eventTriggersStateChanged = Notification.Name("eventTriggersStateChanged")

    /// Posted to request opening the main window
    static let openMainWindow = Notification.Name("openMainWindow")
}
