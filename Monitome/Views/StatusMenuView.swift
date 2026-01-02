//
//  StatusMenuView.swift
//  Monitome
//

import SwiftUI

struct StatusMenuView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Monitome")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.isRecording ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // Recording toggle
            Toggle(isOn: $appState.isRecording) {
                Label(
                    appState.isRecording ? "Recording" : "Paused",
                    systemImage: appState.isRecording ? "record.circle.fill" : "pause.circle"
                )
            }
            .toggleStyle(.switch)

            // Stats
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Today:")
                        .foregroundColor(.secondary)
                    Text("\(StorageManager.shared.todayCount()) screenshots")
                }
                .font(.caption)

                HStack {
                    Text("Storage:")
                        .foregroundColor(.secondary)
                    Text(formatBytes(StorageManager.shared.totalStorageUsed()))
                }
                .font(.caption)
            }

            Divider()

            // Actions
            HStack {
                Button("Open Window") {
                    // Set activation policy to regular (allows window focus)
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)

                    // Find and show the main window
                    for window in NSApp.windows {
                        if window.title == "Monitome" || window.styleMask.contains(.titled) {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                            break
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("Open Folder") {
                    NSWorkspace.shared.open(StorageManager.shared.recordingsRoot)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 260)
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
    StatusMenuView()
}
