//
//  ScreenRecorder.swift
//  Monitome
//
//  Captures periodic screenshots using SCScreenshotManager.
//

import Foundation
@preconcurrency import ScreenCaptureKit
import Combine
import AppKit

// MARK: - Configuration

enum ScreenshotConfig {
    /// Screenshot interval in seconds. Can be changed via UserDefaults.
    static var interval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "screenshotIntervalSeconds")
        return stored > 0 ? stored : 10.0  // Default: 10 seconds
    }

    static func setInterval(_ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: "screenshotIntervalSeconds")
    }
}

private enum Config {
    static let targetHeight: CGFloat = 1080     // Scale screenshots to ~1080p
    static let jpegQuality: CGFloat = 0.85      // Balance quality vs file size
}

// MARK: - State Machine

private enum RecorderState: Equatable {
    case idle
    case starting
    case capturing
    case paused

    var canStart: Bool {
        switch self {
        case .idle, .paused: return true
        case .starting, .capturing: return false
        }
    }
}

// MARK: - Errors

private enum ScreenRecorderError: Error {
    case noDisplay
    case screenshotFailed
    case imageConversionFailed
}

// MARK: - ScreenRecorder

final class ScreenRecorder: NSObject {

    // MARK: - Initialization

    @MainActor
    init(autoStart: Bool = true) {
        super.init()

        wantsRecording = AppState.shared.isRecording

        // Observe the app-wide recording flag
        sub = AppState.shared.$isRecording
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] rec in
                self?.q.async { [weak self] in
                    guard let self else { return }
                    self.wantsRecording = rec

                    if !rec && self.state == .paused {
                        self.state = .idle
                    }

                    rec ? self.start() : self.stop()
                }
            }

        // Active display tracking
        tracker = ActiveDisplayTracker()
        activeDisplaySub = tracker.$activeDisplayID
            .removeDuplicates()
            .sink { [weak self] newID in
                guard let self, let newID else { return }
                self.q.async { [weak self] in self?.handleActiveDisplayChange(newID) }
            }

        // Honor the current flag once
        if autoStart, AppState.shared.isRecording { start() }

        registerForSleepAndLock()
    }

    deinit {
        sub?.cancel()
        activeDisplaySub?.cancel()
    }

    // MARK: - Properties

    private let q = DispatchQueue(label: "com.monitome.recorder", qos: .userInitiated)
    private var captureTimer: DispatchSourceTimer?
    private var sub: AnyCancellable?
    private var activeDisplaySub: AnyCancellable?
    private var state: RecorderState = .idle
    private var wantsRecording = false
    private var tracker: ActiveDisplayTracker!
    private var currentDisplayID: CGDirectDisplayID?
    private var requestedDisplayID: CGDirectDisplayID?

    // ScreenCaptureKit objects
    private var cachedContent: SCShareableContent?
    private var cachedDisplay: SCDisplay?

    // MARK: - Start/Stop

    func start() {
        q.async { [weak self] in
            guard let self else { return }
            guard self.wantsRecording else { return }
            guard self.state.canStart else { return }

            self.state = .starting
            Task { await self.setupCapture() }
        }
    }

    func stop() {
        q.async { [weak self] in
            guard let self else { return }
            self.stopCaptureTimer()
            self.cachedContent = nil
            self.cachedDisplay = nil
            self.currentDisplayID = nil

            if self.state != .paused {
                self.state = .idle
            }
        }
    }

    // MARK: - Capture Setup

    private func setupCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            cachedContent = content

            // Choose display: prefer requested -> active -> first
            let displaysByID: [CGDirectDisplayID: SCDisplay] = Dictionary(
                uniqueKeysWithValues: content.displays.map { ($0.displayID, $0) }
            )
            let trackerID: CGDirectDisplayID? = await MainActor.run { [weak tracker] in tracker?.activeDisplayID }
            let preferredID = requestedDisplayID ?? trackerID

            let display: SCDisplay
            if let pid = preferredID, let scd = displaysByID[pid] {
                display = scd
            } else if let first = content.displays.first {
                display = first
            } else {
                throw ScreenRecorderError.noDisplay
            }

            cachedDisplay = display
            currentDisplayID = display.displayID
            requestedDisplayID = nil

            q.async { [weak self] in
                guard let self else { return }
                guard self.state == .starting else { return }
                self.startCaptureTimer()
                self.state = .capturing

                // Take first screenshot immediately
                Task { await self.captureScreenshot() }
            }

        } catch {
            print("setupCapture failed: \(error.localizedDescription)")
            q.async { [weak self] in
                self?.state = .idle
            }
        }
    }

    // MARK: - Capture Timer

    private func startCaptureTimer() {
        stopCaptureTimer()

        let interval = ScreenshotConfig.interval
        let timer = DispatchSource.makeTimerSource(queue: q)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            Task { await self?.captureScreenshot() }
        }
        timer.resume()
        captureTimer = timer
    }

    private func stopCaptureTimer() {
        captureTimer?.cancel()
        captureTimer = nil
    }

    // MARK: - Screenshot Capture

    /// Public method to trigger an immediate screenshot capture (for event-based triggers)
    func captureNow(reason: TriggerReason) {
        q.async { [weak self] in
            guard let self else { return }
            // Allow capture even if timer isn't running, as long as we have a display
            Task { await self.captureScreenshot(reason: reason) }
        }
    }

    private func captureScreenshot(reason: TriggerReason = .timer) async {
        // For timer-based captures, require capturing state
        // For event-based captures, just need recording enabled and a display
        if reason == .timer {
            guard state == .capturing else { return }
        }
        guard let display = cachedDisplay else {
            // Try to setup if we don't have a display yet
            if cachedDisplay == nil {
                await setupCapture()
            }
            guard let display = cachedDisplay else { return }
            await performCapture(display: display, reason: reason)
            return
        }

        await performCapture(display: display, reason: reason)
    }

    private func performCapture(display: SCDisplay, reason: TriggerReason) async {
        let captureTime = Date()

        do {
            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            let aspectRatio = Double(display.width) / Double(display.height)
            var targetWidth = Int(Double(Config.targetHeight) * aspectRatio)
            if targetWidth % 2 != 0 { targetWidth += 1 }
            var targetHeight = Int(Config.targetHeight)
            if targetHeight % 2 != 0 { targetHeight += 1 }

            config.width = targetWidth
            config.height = targetHeight
            config.scalesToFit = true
            config.showsCursor = true

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Skip duplicate screenshots (only for timer-based captures)
            if reason == .timer {
                if DuplicateDetector.shared.isDuplicate(image, forDisplay: display.displayID) {
                    print("Screenshot skipped (duplicate)")
                    return
                }
            } else {
                // For event-based captures, still update the hash for future comparisons
                DuplicateDetector.shared.updateHash(image, forDisplay: display.displayID)
            }

            guard let jpegData = jpegData(from: image, quality: Config.jpegQuality) else {
                throw ScreenRecorderError.imageConversionFailed
            }

            let fileURL = StorageManager.shared.nextScreenshotURL()
            try jpegData.write(to: fileURL)

            let screenshotId = StorageManager.shared.saveScreenshot(url: fileURL, capturedAt: captureTime, reason: reason)

            // Post notification for analysis integration
            NotificationCenter.default.post(
                name: .screenshotCaptured,
                object: nil,
                userInfo: [
                    "path": fileURL.path,
                    "capturedAt": captureTime,
                    "id": screenshotId as Any,
                    "reason": reason.rawValue
                ]
            )

            let reasonLabel = reason == .timer ? "" : " [\(reason.rawValue)]"
            print("Screenshot saved\(reasonLabel): \(fileURL.lastPathComponent) (\(jpegData.count / 1024)KB)")

        } catch {
            print("Screenshot capture failed: \(error.localizedDescription)")

            if (error as NSError).domain == SCStreamErrorDomain {
                Task { await refreshDisplay() }
            }
        }
    }

    private func refreshDisplay() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            cachedContent = content

            let targetID = requestedDisplayID ?? currentDisplayID

            if let id = targetID,
               let display = content.displays.first(where: { $0.displayID == id }) {
                cachedDisplay = display
                currentDisplayID = id
                if requestedDisplayID == id { requestedDisplayID = nil }
            } else if let first = content.displays.first {
                cachedDisplay = first
                currentDisplayID = first.displayID
            }
        } catch {
            print("Failed to refresh display: \(error)")
        }
    }

    // MARK: - Image Conversion

    private func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }

    // MARK: - Display Change Handling

    private func handleActiveDisplayChange(_ newID: CGDirectDisplayID) {
        requestedDisplayID = newID

        guard wantsRecording else { return }
        guard currentDisplayID != nil, state == .capturing else { return }
        guard newID != currentDisplayID else { return }

        Task { await refreshDisplay() }
    }

    // MARK: - System Events (Sleep/Lock)

    private func registerForSleepAndLock() {
        let nc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        // System will sleep
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    if AppState.shared.isRecording {
                        self.q.async { self.state = .paused }
                    }
                }
            }
            self.stop()
        }

        // System did wake
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { [weak self] in
                guard let self else { return }
                guard self.state == .paused else { return }
                self.resumeRecording(after: 5)
            }
        }

        // Screen locked
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    if AppState.shared.isRecording {
                        self.q.async { self.state = .paused }
                    }
                }
            }
            self.stop()
        }

        // Screen unlocked
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { [weak self] in
                guard let self else { return }
                guard self.state == .paused else { return }
                self.resumeRecording(after: 0.5)
            }
        }

        // Screensaver started
        dnc.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    if AppState.shared.isRecording {
                        self.q.async { self.state = .paused }
                    }
                }
            }
            self.stop()
        }

        // Screensaver stopped
        dnc.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.q.async { [weak self] in
                guard let self else { return }
                guard self.state == .paused else { return }
                self.resumeRecording(after: 0.5)
            }
        }
    }

    private func resumeRecording(after delay: TimeInterval) {
        q.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard AppState.shared.isRecording else { return }
                self.start()
            }
        }
    }
}
