//
//  MainView.swift
//  Monitome
//

import SwiftUI

struct MainView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var agentManager = ActivityAgentManager.shared
    @State private var selectedDate = Date()
    @State private var screenshots: [Screenshot] = []
    @State private var selectedScreenshot: Screenshot?
    @State private var showSettings = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [ActivitySearchResult] = []
    @State private var isSearchingInProgress = false
    @State private var showActivityLog = false
    @AppStorage("indexingEnabled") private var indexingEnabled = true

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
                
                Divider()
                
                // Indexing section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Indexing")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Toggle("", isOn: $indexingEnabled)
                            .toggleStyle(.switch)
                            .scaleEffect(0.7)
                            .labelsHidden()
                    }
                    
                    if agentManager.isAgentAvailable {
                        HStack {
                            Text("\(agentManager.indexedCount) indexed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if agentManager.isIndexing {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                            Spacer()
                            Button(action: { showActivityLog.toggle() }) {
                                Image(systemName: "list.bullet.rectangle")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("View Log")
                        }
                        
                        HStack(spacing: 8) {
                            Button("Index") {
                                Task { await agentManager.indexNewScreenshots() }
                            }
                            .disabled(agentManager.isIndexing)
                            
                            Button("All") {
                                Task { await agentManager.reindexAll() }
                            }
                            .disabled(agentManager.isIndexing)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("Agent not found")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Bottom buttons
                HStack {
                    Button(action: { 
                        NSWorkspace.shared.open(StorageManager.shared.recordingsRoot)
                    }) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .help("Open Recordings Folder")
                    
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .padding()
            }
            .frame(minWidth: 250)
        } detail: {
            // Detail area with toolbar
            VStack(spacing: 0) {
                if isSearching {
                    // Search view
                    ActivitySearchView(
                        searchText: $searchText,
                        searchResults: $searchResults,
                        isSearching: $isSearchingInProgress,
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
                        if !isSearching {
                            searchText = ""
                            searchResults = []
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
            
            // Start periodic indexing when app appears (if enabled)
            if UserDefaults.standard.object(forKey: "indexingEnabled") == nil {
                // Default to enabled
                UserDefaults.standard.set(true, forKey: "indexingEnabled")
            }
            if UserDefaults.standard.bool(forKey: "indexingEnabled") {
                agentManager.startPeriodicIndexing()
            }
        }
        .sheet(item: $selectedScreenshot) { screenshot in
            ScreenshotDetailView(screenshot: screenshot)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showActivityLog) {
            ActivityLogView()
        }
        .onChange(of: indexingEnabled) { _, enabled in
            if enabled {
                agentManager.startPeriodicIndexing()
            } else {
                agentManager.stopPeriodicIndexing()
            }
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

// MARK: - Activity Search View

struct ActivitySearchView: View {
    @Binding var searchText: String
    @Binding var searchResults: [ActivitySearchResult]
    @Binding var isSearching: Bool
    @Binding var selectedScreenshot: Screenshot?
    let onClose: () -> Void
    
    @State private var selectedResult: ActivitySearchResult?
    @FocusState private var isSearchFieldFocused: Bool
    
    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search your activity...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        performSearch()
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                if !searchText.isEmpty && !isSearching {
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
            
            // Search tip
            if searchText.isEmpty && searchResults.isEmpty {
                Text("Try: \"github repo\", \"yesterday VS Code\", \"that article about typescript\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            
            Divider()
                .padding(.top, 8)
            
            // Results
            if searchResults.isEmpty && !searchText.isEmpty && !isSearching {
                Spacer()
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass.circle",
                    description: Text("No activities match '\(searchText)'")
                )
                Spacer()
            } else if searchResults.isEmpty && !isSearching {
                Spacer()
                ContentUnavailableView(
                    "Search Your Activity",
                    systemImage: "magnifyingglass",
                    description: Text("Search through your indexed screenshots")
                )
                Spacer()
            } else {
                ScrollView {
                    // Results count
                    HStack {
                        Text("\(searchResults.count) results")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(searchResults) { result in
                            ActivityResultCard(result: result)
                                .onTapGesture {
                                    selectedResult = result
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
        .sheet(item: $selectedResult) { result in
            ActivityDetailView(result: result)
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        
        Task {
            let results = await ActivityAgentManager.shared.searchFTS(searchText)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
}

// MARK: - Activity Result Card

struct ActivityResultCard: View {
    let result: ActivitySearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            if let image = NSImage(contentsOfFile: result.filePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 140)
                    .cornerRadius(8)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
            }
            
            // Activity summary
            VStack(alignment: .leading, spacing: 4) {
                // App name and time
                HStack {
                    if let appName = result.appName {
                        Text(appName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                    Text(result.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Activity description
                Text(result.activity)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
                // Date
                Text(result.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Tags
                if !result.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(result.tags.prefix(5), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Activity Detail View

struct ActivityDetailView: View {
    let result: ActivitySearchResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    if let appName = result.appName {
                        Text(appName)
                            .font(.headline)
                            .foregroundColor(.accentColor)
                    }
                    HStack {
                        Text(result.timestamp, style: .date)
                        Text(result.timestamp, style: .time)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Screenshot
                    if let image = NSImage(contentsOfFile: result.filePath) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    }
                    
                    // Activity
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity")
                            .font(.headline)
                        Text(result.activity)
                            .font(.body)
                    }
                    
                    // Summary
                    if !result.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.headline)
                            Text(result.summary)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // URL
                    if let url = result.url {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("URL")
                                .font(.headline)
                            Link(url, destination: URL(string: url) ?? URL(string: "about:blank")!)
                                .font(.body)
                        }
                    }
                    
                    // Tags
                    if !result.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.headline)
                            FlowLayout(spacing: 6) {
                                ForEach(result.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0
        
        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            height = y + rowHeight
        }
    }
}

// MARK: - Activity Log View

struct ActivityLogView: View {
    @ObservedObject private var agentManager = ActivityAgentManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity Index Log")
                    .font(.headline)
                Spacer()
                
                if agentManager.isIndexing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Indexing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button("Index Now") {
                    Task {
                        await agentManager.indexNewScreenshots()
                    }
                }
                .disabled(agentManager.isIndexing)
                
                Button(action: { agentManager.clearLog() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Clear Log")
                
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Stats bar
            HStack {
                Text("\(agentManager.indexedCount) indexed")
                Spacer()
                if let lastTime = agentManager.lastIndexTime {
                    Text("Last: \(lastTime, style: .relative) ago")
                }
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            
            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(agentManager.logEntries) { entry in
                            ActivityLogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: agentManager.logEntries.count) { _, _ in
                    if autoScroll, let lastEntry = agentManager.logEntries.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Status bar
            if !agentManager.isAgentAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Activity agent not found. Make sure it's installed.")
                        .font(.caption)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Activity Log Row

struct ActivityLogRow: View {
    let entry: ActivityLogEntry
    
    private var prefix: String {
        switch entry.type {
        case .info: return "·"
        case .success: return "✓"
        case .error: return "✗"
        case .processing: return "→"
        }
    }
    
    private var prefixColor: Color {
        switch entry.type {
        case .info: return .secondary
        case .success: return .green
        case .error: return .red
        case .processing: return .primary
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(prefix)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(prefixColor)
                .frame(width: 12)
            
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(entry.type == .error ? .red : .primary)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    MainView()
}
