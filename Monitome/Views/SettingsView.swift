//
//  SettingsView.swift
//  Monitome
//

import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    var embedded: Bool = false
    var onDone: (() -> Void)? = nil

    @AppStorage("screenshotIntervalSeconds") private var interval: Double = 10
    @AppStorage("storageLimitGB") private var storageLimitGB: Int = 5
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey: String = ""

    @State private var hasAccessibilityPermission = PermissionsManager.isAccessibilityGranted
    @State private var hasScreenRecordingPermission = PermissionsManager.isScreenRecordingGranted
    @State private var showAPIKey = false
    @State private var permissionRefreshTask: Task<Void, Never>?

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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Permissions")
                        .font(.headline)

                    PermissionStatusRow(
                        title: "Screen Recording",
                        description: "Required to capture screenshots",
                        granted: hasScreenRecordingPermission,
                        buttonTitle: "Open Settings",
                        note: "May require reopening Monitome after granting"
                    ) {
                        _ = PermissionsManager.requestScreenRecording()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            PermissionsManager.openScreenRecordingSettings()
                        }
                    }

                    PermissionStatusRow(
                        title: "Accessibility",
                        description: "Optional, enables browser tab detection",
                        granted: hasAccessibilityPermission,
                        buttonTitle: "Open Settings"
                    ) {
                        PermissionsManager.requestAccessibility()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            PermissionsManager.openAccessibilitySettings()
                        }
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

                    HStack(spacing: 8) {
                        Image(systemName: hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(hasAccessibilityPermission ? .green : .orange)

                        Text(hasAccessibilityPermission ? "Accessibility granted" : "Accessibility permission improves browser tab tracking")
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
                
                // AI Indexing Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Indexing")
                        .font(.headline)
                    
                    HStack {
                        if showAPIKey {
                            TextField("Anthropic API Key", text: $anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Anthropic API Key", text: $anthropicAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if anthropicAPIKey.isEmpty {
                        Text("Get key at console.anthropic.com or set ANTHROPIC_API_KEY in ~/.env")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

                if !embedded {
                    Spacer(minLength: 20)

                    HStack {
                        Spacer()
                        Button("Done") {
                            if let onDone {
                                onDone()
                            } else {
                                dismiss()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding()
        }
        .frame(width: embedded ? nil : 420, height: embedded ? nil : 700)
        .onAppear {
            refreshPermissions()
            startPermissionPolling()
        }
        .onDisappear {
            permissionRefreshTask?.cancel()
            permissionRefreshTask = nil
        }
    }

    private func startPermissionPolling() {
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshPermissions() {
        hasAccessibilityPermission = PermissionsManager.isAccessibilityGranted
        hasScreenRecordingPermission = PermissionsManager.isScreenRecordingGranted
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

private struct PermissionStatusRow: View {
    let title: String
    let description: String
    let granted: Bool
    let buttonTitle: String
    var note: String? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !granted {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? Color.green.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(granted ? Color.green.opacity(0.45) : Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
    }
}

#Preview {
    SettingsView(embedded: true)
}
