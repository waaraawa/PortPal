import SwiftUI
import AppKit

struct AutoScrollingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    @Binding var shouldAutoScroll: Bool
    let isPortOpen: Bool
    let highlightSettings: HighlightSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: AutoScrollingTextEditor

        init(_ parent: AutoScrollingTextEditor) {
            self.parent = parent
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView else { return }

            let scrollPosition = scrollView.documentVisibleRect
            let contentHeight = textView.frame.height
            let visibleHeight = scrollView.frame.height

            // Check if user is at or near the bottom
            let isAtBottom = scrollPosition.origin.y + visibleHeight >= contentHeight - 50

            DispatchQueue.main.async {
                self.parent.shouldAutoScroll = isAtBottom
            }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.font = font
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = isPortOpen ? NSColor.textBackgroundColor : NSColor.windowBackgroundColor
        textView.textContainerInset = CGSize(width: 8, height: 8)

        // Add scroll listener
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSScrollView.didLiveScrollNotification,
            object: scrollView
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Update background color based on port status
        textView.backgroundColor = isPortOpen ? NSColor.textBackgroundColor : NSColor.windowBackgroundColor

        if textView.string != text {
            // Apply highlighting to the text
            applyHighlighting(to: textView, text: text)

            if shouldAutoScroll {
                DispatchQueue.main.async {
                    textView.scrollToEndOfDocument(nil)
                }
            }
        }
    }

    private func applyHighlighting(to textView: NSTextView, text: String) {
        let attributedString = NSMutableAttributedString(string: text)

        // Set default attributes
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]
        attributedString.setAttributes(defaultAttributes, range: NSRange(location: 0, length: text.count))

        // Apply highlighting for enabled keywords
        let enabledKeywords = highlightSettings.keywords.filter { $0.isEnabled && !$0.keyword.isEmpty }

        for keyword in enabledKeywords {
            let pattern = NSRegularExpression.escapedPattern(for: keyword.keyword)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }

            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))

            for match in matches {
                let nsColor = NSColor(keyword.swiftUIColor)
                attributedString.addAttribute(.foregroundColor, value: nsColor, range: match.range)
            }
        }

        textView.textStorage?.setAttributedString(attributedString)
    }
}

@main
struct PortPalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    enum UIMode: String, CaseIterable, Identifiable {
        case serialPortSelection = "Ports"
        case highlightSettings = "Highlight"
        case logSave = "Log"
        case commandHistory = "History"
        case macro = "Macro"

        var id: String { self.rawValue }
    }

    @StateObject private var serialPortManager = SerialPortManager()
    @StateObject private var highlightSettings = HighlightSettings()
    @StateObject private var macroSettings = MacroSettings()
    @State private var logEntries: [LogEntry] = []
    @State private var command: String = ""
    @State private var commandHistory: [CommandHistoryItem] = []
    @State private var historySortOption: HistorySortOption = .latest
    @FocusState private var isCommandFieldFocused: Bool
    @State private var currentUIMode: UIMode = .serialPortSelection
    @State private var isLeftPanelVisible = true
    @State private var selectedPortLocal: String?
    @State private var isAutoScrollEnabled = true

    // Performance optimization: debouncing
    @State private var pendingMessages: [LogEntry] = []
    @State private var debounceWorkItem: DispatchWorkItem?

    private let maxLogEntries = 1000
    private let debounceDelay: TimeInterval = 0.1  // 100ms debounce delay
    
    @State private var logSaveURL: URL?
    @State private var logFilename: String = ""

    private let commandHistoryKey = "commandHistoryItems"
    private let historySortOptionKey = "historySortOption"
    private let logSavePathKey = "logSavePathBookmark"

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    init() {
        // Load command history
        if let data = UserDefaults.standard.data(forKey: commandHistoryKey),
           let historyItems = try? JSONDecoder().decode([CommandHistoryItem].self, from: data) {
            _commandHistory = State(initialValue: historyItems)
        } else {
            // Migrate old string array format if exists
            if let oldHistory = UserDefaults.standard.stringArray(forKey: "commandHistory") {
                let migratedItems = oldHistory.map { CommandHistoryItem(command: $0) }
                _commandHistory = State(initialValue: migratedItems)
            } else {
                _commandHistory = State(initialValue: [])
            }
        }

        // Load sort option
        if let sortOptionRaw = UserDefaults.standard.string(forKey: historySortOptionKey),
           let sortOption = HistorySortOption(rawValue: sortOptionRaw) {
            _historySortOption = State(initialValue: sortOption)
        }

        if let bookmarkData = UserDefaults.standard.data(forKey: logSavePathKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale), !isStale {
                _logSaveURL = State(initialValue: url)
            }
        }
    }

    var body: some View {
        HSplitView {
            if isLeftPanelVisible {
                VStack {
                Picker("", selection: $currentUIMode) {
                    ForEach(UIMode.allCases) {
                        mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical)

                // Display different views based on UI mode
                switch currentUIMode {
                case .serialPortSelection:
                    VStack {
                        Form {
                            Picker("Baud Rate", selection: $serialPortManager.baudRate) {
                                ForEach(BaudRate.allCases) { rate in
                                    Text(rate.displayText).tag(rate)
                                }
                            }
                            .onChange(of: serialPortManager.baudRate) { _, _ in serialPortManager.saveSettings() }

                            Picker("Parity", selection: $serialPortManager.parity) {
                                ForEach(Parity.allCases) { parity in
                                    Text(parity.rawValue).tag(parity)
                                }
                            }
                            .onChange(of: serialPortManager.parity) { _, _ in serialPortManager.saveSettings() }

                            Picker("Data Bits", selection: $serialPortManager.dataBits) {
                                ForEach(DataBits.allCases) { bits in
                                    Text("\(bits.rawValue)").tag(bits)
                                }
                            }
                            .onChange(of: serialPortManager.dataBits) { _, _ in serialPortManager.saveSettings() }

                            Picker("Stop Bits", selection: $serialPortManager.stopBits) {
                                ForEach(StopBits.allCases) { bits in
                                    Text("\(bits.rawValue)").tag(bits)
                                }
                            }
                            .onChange(of: serialPortManager.stopBits) { _, _ in serialPortManager.saveSettings() }

                            Picker("Line Ending", selection: $serialPortManager.lineEnding) {
                                ForEach(LineEnding.allCases) { ending in
                                    Text(ending.rawValue).tag(ending)
                                }
                            }
                            .onChange(of: serialPortManager.lineEnding) { _, _ in serialPortManager.saveSettings() }
                        }
                        .disabled(serialPortManager.isOpen)
                        .padding(.horizontal, 12)

                        HStack(alignment: .center, spacing: 12) {
                            Button("Open") {
                                if let port = serialPortManager.selectedPort {
                                    serialPortManager.openPort(path: port)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(serialPortManager.selectedPort == nil || serialPortManager.isOpen)

                            Button("Close") {
                                serialPortManager.closePort()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!serialPortManager.isOpen)

                            Button("Refresh") {
                                serialPortManager.findSerialPorts()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(height: 20)
                        .padding(.horizontal)

                        List(selection: $selectedPortLocal) {
                            ForEach(serialPortManager.serialPorts, id: \.self) { port in
                                Text(port)
                                    .listRowBackground(
                                        (serialPortManager.connectedPortPath == port) ? Color.gray.opacity(0.3) : Color(NSColor.clear)
                                    )
                                    .tag(port)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        TapGesture(count: 2)
                                            .onEnded {
                                                handlePortDoubleClick(port: port)
                                            }
                                            .exclusively(before: TapGesture(count: 1)
                                                .onEnded {
                                                    selectedPortLocal = port
                                                }
                                            )
                                    )
                            }
                        }
                        .onChange(of: selectedPortLocal) { _, newValue in
                            DispatchQueue.main.async {
                                serialPortManager.selectedPort = newValue
                            }
                        }
                        .onChange(of: serialPortManager.selectedPort) { _, newValue in
                            if selectedPortLocal != newValue {
                                selectedPortLocal = newValue
                            }
                        }
                        .onChange(of: serialPortManager.serialPorts) { _, _ in
                            // Ensure selectedPortLocal is in sync when port list changes
                            if selectedPortLocal != serialPortManager.selectedPort {
                                selectedPortLocal = serialPortManager.selectedPort
                            }
                        }
                        .onAppear {
                            selectedPortLocal = serialPortManager.selectedPort
                        }
                    }
                case .highlightSettings:
                    HighlightSettingsView(settings: highlightSettings)
                case .logSave:
                    VStack(alignment: .leading, spacing: 15) {
                        VStack(alignment: .leading) {
                            Text("Directory")
                                .font(.caption)
                            Text(logSaveURL?.path ?? "No directory selected")
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.windowBackgroundColor))
                                .cornerRadius(5)
                        }
                        .disabled(serialPortManager.isLiveLogging)
                        
                        Button("Choose Directory...") {
                            chooseLogDirectory()
                        }
                        .disabled(serialPortManager.isLiveLogging)
                        
                        VStack(alignment: .leading) {
                            Text("File Name")
                                .font(.caption)
                            TextField("Log Filename", text: $logFilename)
                        }
                        .disabled(serialPortManager.isLiveLogging)
                        
                        Spacer() 
                        
                        if serialPortManager.isLiveLogging {
                            Button(action: stopLogging) {
                                HStack {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundColor(.red)
                                    Text("Stop Logging")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button(action: startLogging) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                    Text("Start Logging")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(logSaveURL == nil || logFilename.isEmpty)
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .onAppear(perform: generateFilename)

                case .commandHistory:
                    VStack {
                        HStack {
                            Text("Sort by:")
                                .font(.caption)
                            Picker("", selection: $historySortOption) {
                                ForEach(HistorySortOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: historySortOption) { _, _ in
                                saveHistorySortOption()
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)

                        List {
                            ForEach(sortedCommandHistory) { item in
                                HStack {
                                    Button(action: {
                                        executeCommand(item.command)
                                    }) {
                                        HStack {
                                            Text(item.command)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Text("×\(item.usageCount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)

                                    Button(action: {
                                        removeCommandFromHistory(item.command)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                case .macro:
                    MacroSettingsView(settings: macroSettings, serialPortManager: serialPortManager)
                }
            }
            .frame(width: 300)
            .onAppear {
                serialPortManager.findSerialPorts()
                serialPortManager.onDataReceived = { message in
                    DispatchQueue.main.async {
                        let newEntry = LogEntry(timestamp: Date(), message: message)
                        pendingMessages.append(newEntry)
                        
                        // Cancel previous debounce work
                        debounceWorkItem?.cancel()
                        
                        // Create new debounce work (execute after 100ms)
                        let workItem = DispatchWorkItem {
                            logEntries.append(contentsOf: pendingMessages)
                            pendingMessages.removeAll()
                            
                            // Limit log entries to prevent performance issues
                            if logEntries.count > maxLogEntries {
                                logEntries.removeFirst(logEntries.count - maxLogEntries)
                            }
                            
                            // Check for keyword matches (check last message only)
                            if let lastMessage = logEntries.last {
                                checkForKeywordMatches(in: lastMessage.message)
                            }
                        }
                        
                        debounceWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
                    }
                }
            }
            }

            VStack {
                AutoScrollingTextEditor(
                    text: .constant(logText),
                    font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    shouldAutoScroll: $isAutoScrollEnabled,
                    isPortOpen: serialPortManager.isOpen,
                    highlightSettings: highlightSettings
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(alignment: .bottom, spacing: 6) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLeftPanelVisible.toggle()
                        }
                    }) {
                        Image(systemName: isLeftPanelVisible ? "chevron.left.square" : "chevron.right.square")
                            .foregroundColor(.accentColor)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 20)
                    .help("hide/unhide option panel")

                    Button(action: clearScreen) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .frame(height: 20)
                    .help("Clear screen")

                    TextField("Enter command", text: $command)
                        .textFieldStyle(.plain)
                        .foregroundColor(.primary)
                        .frame(height: 20)
                        .padding(.horizontal, 8)
                        .background(Color.white)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white, lineWidth: 1)
                        )
                        .focused($isCommandFieldFocused)
                        .onSubmit {
                            sendFromTextField()
                        }
                }

                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
        }
        .frame(minWidth: 850, minHeight: 600)
        .onAppear {
            isCommandFieldFocused = true
        }
    }

    var sortedCommandHistory: [CommandHistoryItem] {
        switch historySortOption {
        case .latest:
            return commandHistory.sorted { $0.lastUsed < $1.lastUsed }
        case .usageCount:
            return commandHistory.sorted { $0.usageCount > $1.usageCount }
        }
    }

    func executeCommand(_ commandToExecute: String) {
        let trimmedCommand = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        // Find existing command or create new one
        if let existingIndex = commandHistory.firstIndex(where: { $0.command == trimmedCommand }) {
            // Create a completely new item with incremented count
            let newUsageCount = commandHistory[existingIndex].usageCount + 1
            let updatedItem = CommandHistoryItem(
                id: commandHistory[existingIndex].id,
                command: trimmedCommand,
                usageCount: newUsageCount,
                lastUsed: Date()
            )

            // Remove old item and add new item (this forces SwiftUI to detect change)
            commandHistory.remove(at: existingIndex)
            commandHistory.insert(updatedItem, at: existingIndex)
        } else {
            let newItem = CommandHistoryItem(command: trimmedCommand)
            commandHistory.append(newItem)
        }

        saveCommandHistory()

        serialPortManager.send(trimmedCommand + serialPortManager.lineEnding.stringValue)
        isCommandFieldFocused = true
    }

    func sendFromTextField() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedCommand.isEmpty {
            // Send just line ending if command is empty
            serialPortManager.send(serialPortManager.lineEnding.stringValue)
        } else {
            // Execute the command (which includes adding to history)
            executeCommand(command)
        }

        command = ""
    }
    
    func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            if let url = panel.url {
                self.logSaveURL = url
                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: logSavePathKey)
                } catch {
                    print("Error saving bookmark: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func startLogging() {
        guard let directoryURL = logSaveURL else { return }

        guard directoryURL.startAccessingSecurityScopedResource() else {
            print("Failed to start accessing security-scoped resource.")
            return
        }
        defer { directoryURL.stopAccessingSecurityScopedResource() }

        let fileURL = directoryURL.appendingPathComponent(logFilename)

        // Write existing logs first
        let logContent = logEntries.map { "[\(dateFormatter.string(from: $0.timestamp))] \($0.message)" }.joined(separator: "\n") + "\n"

        do {
            try logContent.write(to: fileURL, atomically: true, encoding: .utf8)
            serialPortManager.startLiveLogging(fileURL: fileURL)
        } catch {
            print("Failed to write initial log: \(error.localizedDescription)")
        }
    }
    
    func stopLogging() {
        serialPortManager.stopLiveLogging()
    }

    func generateFilename() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmm"
        if !serialPortManager.isLiveLogging {
            self.logFilename = formatter.string(from: Date()) + ".log"
        }
    }

    func removeCommandFromHistory(_ commandToRemove: String) {
        commandHistory.removeAll { $0.command == commandToRemove }
        saveCommandHistory()
    }

    func saveCommandHistory() {
        if let data = try? JSONEncoder().encode(commandHistory) {
            UserDefaults.standard.set(data, forKey: commandHistoryKey)
        }
    }

    func saveHistorySortOption() {
        UserDefaults.standard.set(historySortOption.rawValue, forKey: historySortOptionKey)
    }

    func clearScreen() {
        logEntries.removeAll()
    }

    func handlePortDoubleClick(port: String) {
        // Set port to selected state
        serialPortManager.selectedPort = port
        selectedPortLocal = port

        // Check if the port is currently connected
        if serialPortManager.connectedPortPath == port && serialPortManager.isOpen {
            // Close if port is already open
            serialPortManager.closePort()
        } else {
            // Open if port is closed
            serialPortManager.openPort(path: port)
        }
    }

    var logText: String {
        logEntries.map { entry in
            "[\(dateFormatter.string(from: entry.timestamp))] \(entry.message)"
        }.joined(separator: "\n")
    }

    func highlightedText(for message: String) -> Text {
        var result: Text = Text("")

        let keywords = highlightSettings.keywords.filter { $0.isEnabled && !$0.keyword.isEmpty }
        guard !keywords.isEmpty else {
            return Text(message)
        }

        let pattern = keywords.map { NSRegularExpression.escapedPattern(for: $0.keyword) }.joined(separator: "|")

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return Text(message)
        }

        let matches = regex.matches(in: message, options: [], range: NSRange(message.startIndex..., in: message))

        var lastIndex = message.startIndex
        for match in matches {
            guard let range = Range(match.range, in: message) else { continue }

            if range.lowerBound > lastIndex {
                result = result + Text(message[lastIndex..<range.lowerBound])
            }

            let keywordString = String(message[range])
            if let highlight = keywords.first(where: { $0.keyword == keywordString }) {
                result = result + Text(keywordString).foregroundColor(highlight.swiftUIColor)
            }

            lastIndex = range.upperBound
        }

        if lastIndex < message.endIndex {
            result = result + Text(message[lastIndex...])
        }

        return result
    }

    func checkForKeywordMatches(in message: String) {
        let enabledKeywords = highlightSettings.keywords.filter { $0.isEnabled && !$0.keyword.isEmpty && $0.isNotificationEnabled }

        guard !enabledKeywords.isEmpty else { return }

        for keyword in enabledKeywords {
            if message.localizedCaseInsensitiveContains(keyword.keyword) {
                highlightSettings.triggerNotification(for: keyword, text: message)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
