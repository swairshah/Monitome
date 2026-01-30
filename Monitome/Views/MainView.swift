//
//  MainView.swift
//  Monitome
//

import SwiftUI

enum MainTab {
    case search
    case chat
    case dayActivity  // Shows activity for selected date
}

struct MainView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var agentManager = ActivityAgentManager.shared
    @State private var selectedDate = Date()
    @State private var screenshots: [Screenshot] = []
    @State private var selectedScreenshot: Screenshot?
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var searchResults: [ActivitySearchResult] = []
    @State private var isSearchingInProgress = false
    @State private var showActivityLog = false
    @State private var selectedTab: MainTab = .search
    @State private var previousTab: MainTab = .search  // To restore after closing day view
    @State private var dayActivities: [ActivitySearchResult] = []
    @State private var isLoadingDayActivities = false
    @AppStorage("indexingEnabled") private var indexingEnabled = true

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
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
            VStack(spacing: 0) {
                // Tab icons
                HStack(spacing: 4) {
                    Button(action: { selectedTab = .search }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 24)
                            .background(selectedTab == .search ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { selectedTab = .chat }) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 24)
                            .background(selectedTab == .chat ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Divider()
                    .padding(.top, 8)
                
                // Tab content
                switch selectedTab {
                case .search:
                    SearchTabView(
                        searchText: $searchText,
                        searchResults: $searchResults,
                        isSearching: $isSearchingInProgress,
                        columns: columns,
                        performSearch: performSearch
                    )
                case .chat:
                    AgentChatView()
                case .dayActivity:
                    DayActivityView(
                        date: selectedDate,
                        activities: dayActivities,
                        screenshots: screenshots,
                        isLoading: isLoadingDayActivities,
                        onClose: closeDayActivityView
                    )
                }
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            loadScreenshots(for: newDate)
            // Show day activity view when date is selected
            if selectedTab != .dayActivity {
                previousTab = selectedTab
            }
            selectedTab = .dayActivity
            loadDayActivities(for: newDate)
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
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isSearchingInProgress = true
        
        Task {
            let results = await agentManager.searchFTS(searchText)
            await MainActor.run {
                searchResults = results
                isSearchingInProgress = false
            }
        }
    }

    private func loadScreenshots(for date: Date) {
        screenshots = StorageManager.shared.fetchForDay(date)
    }
    
    private func loadDayActivities(for date: Date) {
        isLoadingDayActivities = true
        dayActivities = []
        
        Task {
            let activities = await agentManager.getActivitiesForDate(date)
            await MainActor.run {
                dayActivities = activities
                isLoadingDayActivities = false
            }
        }
    }
    
    private func closeDayActivityView() {
        selectedTab = previousTab
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

// MARK: - Search Tab View

struct SearchTabView: View {
    @Binding var searchText: String
    @Binding var searchResults: [ActivitySearchResult]
    @Binding var isSearching: Bool
    let columns: [GridItem]
    let performSearch: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search your activity...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        performSearch()
                    }
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                if !searchText.isEmpty && !isSearching {
                    Button(action: { searchText = ""; searchResults = [] }) {
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
            
            // Results or empty state
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
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search Your Activity")
                        .font(.headline)
                    Text("Try: \"github repo\", \"yesterday in VS Code\", \"that article about typescript\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView {
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
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Day Activity View

struct DayActivityView: View {
    let date: Date
    let activities: [ActivitySearchResult]
    let screenshots: [Screenshot]
    let isLoading: Bool
    let onClose: () -> Void
    
    @State private var selectedActivity: ActivitySearchResult?
    
    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                VStack(alignment: .leading) {
                    Text(date, style: .date)
                        .font(.headline)
                    Text("\(activities.isEmpty ? screenshots.count : activities.count) \(activities.isEmpty ? "screenshots" : "activities")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading activities...")
                Spacer()
            } else if !activities.isEmpty {
                // Show indexed activities
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(activities) { activity in
                            DayActivityCard(activity: activity, selectedActivity: $selectedActivity)
                        }
                    }
                    .padding()
                }
            } else if !screenshots.isEmpty {
                // Fallback: show screenshots (not yet indexed)
                VStack {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.orange)
                        Text("Not yet indexed. Showing raw screenshots.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(screenshots) { screenshot in
                                UnindexedScreenshotCard(screenshot: screenshot)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                Spacer()
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("No screenshots captured on this day")
                )
                Spacer()
            }
        }
        .sheet(item: $selectedActivity) { activity in
            ActivityDetailView(result: activity)
        }
    }
}

// MARK: - Day Activity Card (shows analysis instead of screenshot)

struct DayActivityCard: View {
    let activity: ActivitySearchResult
    @Binding var selectedActivity: ActivitySearchResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Activity content (instead of screenshot thumbnail)
            VStack(alignment: .leading, spacing: 6) {
                // App and time
                HStack {
                    if let appName = activity.appName {
                        Text(appName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }
                    Spacer()
                    Text(activity.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Activity description
                Text(activity.activity)
                    .font(.subheadline)
                    .lineLimit(3)
                
                // Summary if available
                if !activity.summary.isEmpty {
                    Text(activity.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                
                // URL if available (clickable)
                if let urlString = activity.url, !urlString.isEmpty,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text(urlString)
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                // Tags
                if !activity.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(activity.tags.prefix(6), id: \.self) { tag in
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
            .frame(minHeight: 100)
            
            // Show screenshot button
            Button {
                selectedActivity = activity
            } label: {
                HStack {
                    Image(systemName: "photo")
                    Text("View Screenshot")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Unindexed Screenshot Card (for days not yet indexed)

struct UnindexedScreenshotCard: View {
    let screenshot: Screenshot
    @State private var showDetail = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            if let image = NSImage(contentsOfFile: screenshot.filePath) {
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
            
            // Time
            HStack {
                Text(Date(timeIntervalSince1970: TimeInterval(screenshot.capturedAt)), style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .onTapGesture {
            showDetail = true
        }
        .sheet(isPresented: $showDetail) {
            ScreenshotDetailView(screenshot: screenshot)
        }
    }
}

// MARK: - Agent Chat View

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let isUser: Bool
    let text: String
    var screenshots: [String] = []
    var timestamp: Date = Date()
}

class ChatHistory: ObservableObject {
    static let shared = ChatHistory()
    
    @Published var messages: [ChatMessage] = []
    
    private let historyURL: URL
    
    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Monitome")
        historyURL = appSupport.appendingPathComponent("chat-history.json")
        load()
    }
    
    func load() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyURL)
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            print("Failed to load chat history: \(error)")
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: historyURL)
        } catch {
            print("Failed to save chat history: \(error)")
        }
    }
    
    func addMessage(_ message: ChatMessage) {
        messages.append(message)
        save()
    }
    
    func clear() {
        messages.removeAll()
        save()
    }
}

struct AgentChatView: View {
    @ObservedObject private var piAgent = PiAgentManager.shared
    @ObservedObject private var activityAgent = ActivityAgentManager.shared
    @ObservedObject private var chatHistory = ChatHistory.shared
    @State private var inputText = ""
    @State private var isProcessing = false
    @FocusState private var isInputFocused: Bool
    
    /// Use Pi if available, otherwise fall back to activity-agent
    private var usePi: Bool {
        piAgent.isPiAvailable && piAgent.isExtensionAvailable
    }
    
    private let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Monitome/recordings")
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if chatHistory.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ask anything about your activity")
                                    .font(.headline)
                                
                                Text("Search:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\"What was I working on yesterday?\"\n\"Show me GitHub activity from last week\"\n\"Find that article about TypeScript\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("Teach:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                Text("\"Remember that for VS Code, always note the git branch\"\n\"CLI should also match terminal and command line\"\n\"Show me the current rules\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        ForEach(chatHistory.messages) { message in
                            ChatBubble(message: message, dataDir: dataDir)
                                .id(message.id)
                        }
                        
                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: chatHistory.messages.count) { _, _ in
                    if let last = chatHistory.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input + clear button
            HStack(spacing: 8) {
                if !chatHistory.messages.isEmpty {
                    Button(action: { chatHistory.clear() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear chat history")
                }
                
                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty || isProcessing ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isProcessing)
            }
            .padding(12)
        }
        .onAppear {
            isInputFocused = true
            // Scroll to bottom on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // trigger scroll
            }
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }
        
        chatHistory.addMessage(ChatMessage(isUser: true, text: text))
        inputText = ""
        isProcessing = true
        
        Task {
            let response: String
            if usePi {
                // Pi handles session persistence internally via --continue
                response = await piAgent.chat(text)
            } else {
                // Fall back to activity-agent chat
                let history = chatHistory.messages.dropLast().map { (isUser: $0.isUser, text: $0.text) }
                response = await activityAgent.chat(text, history: Array(history))
            }
            await MainActor.run {
                // Extract screenshot filenames from response
                let screenshots = extractScreenshots(from: response)
                chatHistory.addMessage(ChatMessage(isUser: false, text: response, screenshots: screenshots))
                isProcessing = false
            }
        }
    }
    
    private func extractScreenshots(from text: String) -> [String] {
        // Match patterns like: Screenshot: 20260127_143052123.jpg
        let pattern = #"Screenshot:\s*(\d{8}_\d{9}\.jpg)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    let dataDir: URL
    @State private var selectedScreenshot: String?
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            Text(message.isUser ? "You" : "Agent")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if message.isUser {
                Text(message.text)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(12)
                    .textSelection(.enabled)
            } else {
                // Parse and render agent response
                let parsed = parseAgentResponse(message.text)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Show tool calls as pills
                    if !parsed.tools.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(parsed.tools, id: \.self) { tool in
                                HStack(spacing: 4) {
                                    Image(systemName: toolIcon(for: tool))
                                        .font(.caption2)
                                    Text(toolLabel(for: tool))
                                        .font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    // Render markdown content
                    Text(parseMarkdown(parsed.content))
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Show screenshot thumbnails if any
            if !message.screenshots.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(message.screenshots.prefix(6), id: \.self) { filename in
                            ScreenshotThumbnail(filename: filename, dataDir: dataDir)
                                .onTapGesture {
                                    selectedScreenshot = filename
                                }
                        }
                        if message.screenshots.count > 6 {
                            Text("+\(message.screenshots.count - 6)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, height: 40)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .sheet(item: $selectedScreenshot) { filename in
            ChatScreenshotDetailView(filename: filename, dataDir: dataDir)
        }
    }
    
    private struct ParsedResponse {
        var tools: [String]
        var content: String
    }
    
    private func parseAgentResponse(_ text: String) -> ParsedResponse {
        var tools: [String] = []
        var content = text
        
        // Extract tool calls like "[search_fulltext] ✓" or "[get_status] ✓"
        let pattern = #"\[([\w_]+)\]\s*[✓✗]?\s*"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            
            for match in matches {
                if let toolRange = Range(match.range(at: 1), in: text) {
                    tools.append(String(text[toolRange]))
                }
            }
            
            // Remove tool prefixes from content
            content = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ParsedResponse(tools: tools, content: content)
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            var attributed = try AttributedString(markdown: text, options: options)
            
            // Make URLs clickable - find URLs in the text and add link attributes
            let urlPattern = #"https?://[^\s\)\]\>]+"#
            if let regex = try? NSRegularExpression(pattern: urlPattern) {
                let nsString = text as NSString
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    if let range = Range(match.range, in: text),
                       let url = URL(string: String(text[range])),
                       let attrRange = attributed.range(of: String(text[range])) {
                        attributed[attrRange].link = url
                        attributed[attrRange].foregroundColor = .accentColor
                    }
                }
            }
            
            return attributed
        } catch {
            return AttributedString(text)
        }
    }
    
    private func toolIcon(for tool: String) -> String {
        switch tool {
        case "search_fulltext", "search_combined": return "magnifyingglass"
        case "search_by_date", "search_by_date_range": return "calendar"
        case "search_by_app": return "app"
        case "get_status": return "chart.bar"
        case "show_rules": return "list.bullet"
        case "update_rules": return "pencil"
        case "undo_rule_change": return "arrow.uturn.backward"
        case "list_apps": return "square.grid.2x2"
        case "list_dates": return "calendar.badge.clock"
        default: return "gearshape"
        }
    }
    
    private func toolLabel(for tool: String) -> String {
        switch tool {
        case "search_fulltext": return "Search"
        case "search_combined": return "Search"
        case "search_by_date": return "By Date"
        case "search_by_date_range": return "Date Range"
        case "search_by_app": return "By App"
        case "get_status": return "Status"
        case "show_rules": return "Rules"
        case "update_rules": return "Update Rules"
        case "undo_rule_change": return "Undo"
        case "list_apps": return "Apps"
        case "list_dates": return "Dates"
        default: return tool.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct ScreenshotThumbnail: View {
    let filename: String
    let dataDir: URL
    
    var body: some View {
        let imagePath = dataDir.appendingPathComponent(filename)
        
        Group {
            if let nsImage = NSImage(contentsOf: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 50)
                    .clipped()
                    .cornerRadius(6)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 50)
                    .cornerRadius(6)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
}

struct ChatScreenshotDetailView: View {
    let filename: String
    let dataDir: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        let imagePath = dataDir.appendingPathComponent(filename)
        
        VStack {
            HStack {
                Text(formatFilename(filename))
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            
            if let nsImage = NSImage(contentsOf: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ContentUnavailableView("Image not found", systemImage: "photo")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func formatFilename(_ filename: String) -> String {
        // 20260127_143052123.jpg -> 2026-01-27 14:30:52
        let name = filename.replacingOccurrences(of: ".jpg", with: "")
        guard name.count >= 15 else { return filename }
        
        let year = name.prefix(4)
        let month = name.dropFirst(4).prefix(2)
        let day = name.dropFirst(6).prefix(2)
        let hour = name.dropFirst(9).prefix(2)
        let min = name.dropFirst(11).prefix(2)
        let sec = name.dropFirst(13).prefix(2)
        
        return "\(year)-\(month)-\(day) \(hour):\(min):\(sec)"
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
