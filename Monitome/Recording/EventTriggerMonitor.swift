//
//  EventTriggerMonitor.swift
//  Monitome
//
//  Monitors system events to trigger screenshots on app switches and browser tab changes.
//

import Foundation
import AppKit
import Combine

// MARK: - Browser Info

private struct BrowserInfo {
    let bundleId: String
    let name: String

    static let supported: [BrowserInfo] = [
        BrowserInfo(bundleId: "com.google.Chrome", name: "Chrome"),
        BrowserInfo(bundleId: "com.apple.Safari", name: "Safari"),
        BrowserInfo(bundleId: "company.thebrowser.Browser", name: "Arc"),
        BrowserInfo(bundleId: "org.mozilla.firefox", name: "Firefox"),
        BrowserInfo(bundleId: "com.brave.Browser", name: "Brave"),
        BrowserInfo(bundleId: "com.microsoft.edgemac", name: "Edge"),
    ]

    static func isBrowser(bundleId: String?) -> Bool {
        guard let id = bundleId else { return false }
        return supported.contains { $0.bundleId == id }
    }
}

// MARK: - Event Trigger Monitor

@MainActor
final class EventTriggerMonitor: ObservableObject {

    // MARK: - Properties

    @Published private(set) var isMonitoring = false
    @Published private(set) var hasAccessibilityPermission = false

    private var appSwitchObserver: Any?
    private var browserPollTimer: Timer?
    private var lastWindowTitle: String?
    private var lastCaptureTime: Date?
    private var lastAppBundleId: String?

    // Callback to trigger screenshot
    var onTrigger: ((TriggerReason) -> Void)?

    // Configuration
    private let debounceInterval: TimeInterval = 2.0  // Minimum seconds between captures
    private let browserPollInterval: TimeInterval = 1.0  // How often to check browser title

    // MARK: - Initialization

    init() {
        checkAccessibilityPermission()
    }

    deinit {
        // Clean up observers directly since stop() is MainActor-isolated
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        browserPollTimer?.invalidate()
    }

    // MARK: - Permission

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Check again after a delay (user might grant permission)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkAccessibilityPermission()
        }
    }

    // MARK: - Start/Stop

    func start() {
        guard !isMonitoring else { return }

        setupAppSwitchObserver()
        setupBrowserTitlePolling()

        isMonitoring = true
        print("EventTriggerMonitor: Started monitoring")
    }

    func stop() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }

        browserPollTimer?.invalidate()
        browserPollTimer = nil

        isMonitoring = false
        print("EventTriggerMonitor: Stopped monitoring")
    }

    // MARK: - App Switch Detection

    private func setupAppSwitchObserver() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppSwitch(notification)
        }
    }

    private func handleAppSwitch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        // Skip if same app (can happen with multiple windows)
        guard bundleId != lastAppBundleId else { return }
        lastAppBundleId = bundleId

        // Reset window title tracking when switching apps
        lastWindowTitle = nil

        // Trigger screenshot if debounce allows
        if shouldCapture() {
            print("EventTriggerMonitor: App switch to \(app.localizedName ?? bundleId)")
            triggerCapture(reason: .appSwitch)
        }
    }

    // MARK: - Browser Tab Detection

    private func setupBrowserTitlePolling() {
        // Only poll if we have accessibility permission
        guard hasAccessibilityPermission else {
            print("EventTriggerMonitor: Skipping browser polling (no accessibility permission)")
            return
        }

        browserPollTimer = Timer.scheduledTimer(withTimeInterval: browserPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollBrowserTitle()
            }
        }
    }

    private func pollBrowserTitle() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier,
              BrowserInfo.isBrowser(bundleId: bundleId) else {
            return
        }

        // Get the window title using Accessibility API
        guard let windowTitle = getWindowTitle(for: frontApp) else { return }

        // Check if title changed (indicates tab switch)
        if let lastTitle = lastWindowTitle, lastTitle != windowTitle {
            if shouldCapture() {
                print("EventTriggerMonitor: Tab change in \(frontApp.localizedName ?? bundleId): \(windowTitle.prefix(50))...")
                triggerCapture(reason: .tabChange)
            }
        }

        lastWindowTitle = windowTitle
    }

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success,
              let windows = windowsRef as? [AXUIElement],
              let firstWindow = windows.first else {
            return nil
        }

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleRef)

        guard titleResult == .success,
              let title = titleRef as? String else {
            return nil
        }

        return title
    }

    // MARK: - Debouncing

    private func shouldCapture() -> Bool {
        guard let last = lastCaptureTime else { return true }
        return Date().timeIntervalSince(last) >= debounceInterval
    }

    private func triggerCapture(reason: TriggerReason) {
        lastCaptureTime = Date()
        onTrigger?(reason)
    }
}

// MARK: - Notification for Settings UI

extension Notification.Name {
    static let accessibilityPermissionChanged = Notification.Name("accessibilityPermissionChanged")
}
