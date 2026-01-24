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
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [Screenshot] = []

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
            // Detail area with toolbar
            VStack(spacing: 0) {
                if isSearching {
                    // Search view
                    SearchView(
                        searchText: $searchText,
                        searchResults: $searchResults,
                        selectedScreenshot: $selectedScreenshot,
                        onClose: {
                            isSearching = false
                            searchText = ""
                            searchResults = []
                        }
                    )
                } else {
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
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        isSearching.toggle()
                        if isSearching {
                            // Load recent screenshots for search
                            searchResults = StorageManager.shared.fetchRecent(limit: 200)
                        }
                    }) {
                        Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                            .foregroundColor(isSearching ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isSearching ? "Close Search" : "Search Screenshots")
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

// MARK: - Search View

struct SearchView: View {
    @Binding var searchText: String
    @Binding var searchResults: [Screenshot]
    @Binding var selectedScreenshot: Screenshot?
    let onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)
    ]

    private var filteredResults: [Screenshot] {
        if searchText.isEmpty {
            return searchResults
        }
        // Filter by date string (for now, since we don't have text content)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return searchResults.filter { screenshot in
            let dateString = formatter.string(from: screenshot.capturedDate).lowercased()
            return dateString.contains(searchText.lowercased())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search by date...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Results
            if filteredResults.isEmpty {
                Spacer()
                ContentUnavailableView(
                    searchText.isEmpty ? "Search Screenshots" : "No Results",
                    systemImage: searchText.isEmpty ? "magnifyingglass" : "magnifyingglass.circle",
                    description: Text(searchText.isEmpty ? "Type to search through your screenshots" : "No screenshots match '\(searchText)'")
                )
                Spacer()
            } else {
                ScrollView {
                    // Results count
                    HStack {
                        Text("\(filteredResults.count) screenshots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredResults) { screenshot in
                            SearchResultCard(screenshot: screenshot)
                                .onTapGesture {
                                    selectedScreenshot = screenshot
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}

// MARK: - Search Result Card

struct SearchResultCard: View {
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

            // Date and time
            VStack(alignment: .leading, spacing: 2) {
                Text(screenshot.capturedDate, style: .date)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(screenshot.capturedDate, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(4)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    MainView()
}
