//
//  AppDelegate.swift
//  Monitome
//

import AppKit
import Combine
import KeyboardShortcuts

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder: ScreenRecorder!
    private var eventMonitor: EventTriggerMonitor!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar controller
        statusBar = StatusBarController()

        // Initialize recorder (waits for permission)
        AppState.shared.isRecording = false
        recorder = ScreenRecorder(autoStart: false)

        // Initialize event trigger monitor
        eventMonitor = EventTriggerMonitor()
        eventMonitor.onTrigger = { [weak self] reason in
            self?.recorder.captureNow(reason: reason)
        }

        // Observe both isRecording and eventTriggersEnabled
        // Event monitor should only run when BOTH are true
        Publishers.CombineLatest(
            AppState.shared.$isRecording,
            AppState.shared.$eventTriggersEnabled
        )
        .sink { [weak self] isRecording, eventTriggersEnabled in
            if isRecording && eventTriggersEnabled {
                self?.eventMonitor.start()
            } else {
                self?.eventMonitor.stop()
            }
        }
        .store(in: &cancellables)

        // Register keyboard shortcuts
        setupKeyboardShortcuts()
        
        // Start activity agent indexing
        ActivityAgentManager.shared.startPeriodicIndexing()

        // Restore recording state only if required permission is already granted
        let savedPref = UserDefaults.standard.bool(forKey: "isRecording")
        if PermissionsManager.isScreenRecordingGranted {
            AppState.shared.isRecording = savedPref
        } else {
            print("Screen recording permission not granted")
            AppState.shared.isRecording = false
            NotificationCenter.default.post(name: .showPermissionsOnboarding, object: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar when window is closed
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop recording gracefully
        AppState.shared.isRecording = false
        eventMonitor.stop()
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureNow) { [weak self] in
            self?.recorder.captureNow(reason: .manual)
        }

        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            AppState.shared.isRecording.toggle()
        }
    }
}
