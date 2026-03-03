//
//  PermissionsManager.swift
//  Monitome
//

import AppKit
import CoreGraphics

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

enum PermissionsManager {
    // MARK: - Checks

    static func checkScreenRecording() -> PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    static func checkAccessibility() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    static var isScreenRecordingGranted: Bool {
        checkScreenRecording() == .granted
    }

    static var isAccessibilityGranted: Bool {
        checkAccessibility() == .granted
    }

    // MARK: - Requests

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Open Settings

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
