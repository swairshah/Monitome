//
//  SettingsView.swift
//  Monitome
//

import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @AppStorage("screenshotIntervalSeconds") private var interval: Double = 10
    @AppStorage("storageLimitGB") private var storageLimitGB: Int = 5

    @State private var hasAccessibilityPermission = AXIsProcessTrusted()

    private let intervalOptions: [Double] = [5, 10, 15, 30, 60]
    private let storageLimitOptions: [Int] = [1, 2, 5, 10, 20, 50]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Divider()

                // Permissions Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Permissions")
                        .font(.headline)

                    Text("If macOS prompts fail to open the correct page, use these buttons:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button("Screen Recording") {
                            openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)

                        Button("Accessibility") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // Event Triggers Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Triggers")
                        .font(.headline)

                    Toggle(isOn: $appState.eventTriggersEnabled) {
                        VStack(alignment: .leading) {
                            Text("Capture on app/tab switch")
                            Text("Takes a screenshot when you switch apps or browser tabs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    // Accessibility permission status
                    HStack(spacing: 8) {
                        Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(hasAccessibilityPermission ? .green : .orange)

                        Text(hasAccessibilityPermission ? "Accessibility: Granted" : "Accessibility: Required for tab detection")
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }

                Divider()

                // Keyboard Shortcuts Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keyboard Shortcuts")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Text("Capture Now:")
                                .frame(width: 120, alignment: .trailing)
                            KeyboardShortcuts.Recorder(for: .captureNow)
                        }

                        GridRow {
                            Text("Toggle Recording:")
                                .frame(width: 120, alignment: .trailing)
                            KeyboardShortcuts.Recorder(for: .toggleRecording)
                        }
                    }

                    Text("Global shortcuts work even when the app is in the background")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Screenshot interval
                VStack(alignment: .leading, spacing: 8) {
                    Text("Timer Interval")
                        .font(.headline)

                    Picker("Interval", selection: $interval) {
                        ForEach(intervalOptions, id: \.self) { seconds in
                            Text(formatInterval(seconds)).tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Time-based capture runs alongside event triggers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Storage limit
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Limit")
                        .font(.headline)

                    Picker("Storage", selection: $storageLimitGB) {
                        ForEach(storageLimitOptions, id: \.self) { gb in
                            Text("\(gb) GB").tag(gb)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Old screenshots are automatically deleted when limit is reached")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Storage info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Info")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        GridRow {
                            Text("Location:")
                                .foregroundColor(.secondary)
                            Text(StorageManager.shared.recordingsRoot.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        GridRow {
                            Text("Used:")
                                .foregroundColor(.secondary)
                            Text(formatBytes(StorageManager.shared.totalStorageUsed()))
                        }

                        GridRow {
                            Text("Screenshots:")
                                .foregroundColor(.secondary)
                            Text("\(StorageManager.shared.screenshotCount())")
                        }
                    }
                    .font(.caption)

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(StorageManager.shared.recordingsRoot)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                Spacer(minLength: 20)

                // Done button
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 420, height: 700)
        .onAppear {
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }

    private func openScreenRecordingSettings() {
        // Use shell command to reliably open Screen Recording settings on macOS 13+
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]
        try? task.run()
    }

    private func openAccessibilitySettings() {
        // Use shell command to reliably open Accessibility settings on macOS 13+
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? task.run()

        // Check permission again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            hasAccessibilityPermission = AXIsProcessTrusted()
        }
    }

    private func formatInterval(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            return "\(Int(seconds / 60))m"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024)
        }
    }
}

#Preview {
    SettingsView()
}
