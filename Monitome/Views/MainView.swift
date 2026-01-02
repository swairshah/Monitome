//
//  MainView.swift
//  Monitome
//

import SwiftUI

struct MainView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedDate = Date()
    @State private var screenshots: [Screenshot] = []
    @State private var selectedScreenshot: Screenshot?
    @State private var showSettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
    ]

    var body: some View {
        NavigationSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 16) {
                // Recording status
                HStack {
                    Circle()
                        .fill(appState.isRecording ? Color.red : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(appState.isRecording ? "Recording" : "Paused")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $appState.isRecording)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal)

                Divider()

                // Date picker
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)

                Divider()

                // Stats
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(screenshots.count) screenshots", systemImage: "photo.stack")
                    Label(formatBytes(StorageManager.shared.totalStorageUsed()), systemImage: "internaldrive")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

                Spacer()

                // Settings button
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .padding()
            }
            .frame(minWidth: 250)
        } detail: {
            // Screenshot grid
            if screenshots.isEmpty {
                ContentUnavailableView(
                    "No Screenshots",
                    systemImage: "photo.badge.plus",
                    description: Text("Screenshots for this day will appear here")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(screenshots) { screenshot in
                            ScreenshotCard(screenshot: screenshot)
                                .onTapGesture {
                                    selectedScreenshot = screenshot
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            loadScreenshots(for: newDate)
        }
        .onAppear {
            loadScreenshots(for: selectedDate)
            setupNotificationObserver()
        }
        .sheet(item: $selectedScreenshot) { screenshot in
            ScreenshotDetailView(screenshot: screenshot)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func loadScreenshots(for date: Date) {
        screenshots = StorageManager.shared.fetchForDay(date)
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .screenshotCaptured,
            object: nil,
            queue: .main
        ) { _ in
            // Reload if viewing today
            if Calendar.current.isDateInToday(selectedDate) {
                loadScreenshots(for: selectedDate)
            }
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

// MARK: - Screenshot Card

struct ScreenshotCard: View {
    let screenshot: Screenshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Thumbnail
            if let image = NSImage(contentsOfFile: screenshot.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 120)
                    .cornerRadius(8)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
            }

            // Time
            Text(screenshot.capturedDate, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Screenshot Detail View

struct ScreenshotDetailView: View {
    let screenshot: Screenshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            // Header
            HStack {
                Text(screenshot.capturedDate, style: .date)
                Text(screenshot.capturedDate, style: .time)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            // Full image
            if let image = NSImage(contentsOfFile: screenshot.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            } else {
                ContentUnavailableView("Image Not Found", systemImage: "photo")
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    MainView()
}
