import SwiftUI
import AppKit

struct AutoScrollingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    @Binding var shouldAutoScroll: Bool
    let isPortOpen: Bool

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
            textView.string = text

            if shouldAutoScroll {
                DispatchQueue.main.async {
                    textView.scrollToEndOfDocument(nil)
                }
            }
        }
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
        case logSave = "Log Save"
        case commandHistory = "History"

        var id: String { self.rawValue }
    }

    @StateObject private var serialPortManager = SerialPortManager()
    @StateObject private var highlightSettings = HighlightSettings()
    @State private var logEntries: [LogEntry] = []
    @State private var command: String = ""
    @State private var commandHistory: [String]
    @FocusState private var isCommandFieldFocused: Bool
    @State private var currentUIMode: UIMode = .serialPortSelection
    @State private var isLeftPanelVisible = true
    @State private var selectedPortLocal: String?
    @State private var isAutoScrollEnabled = true

    private let maxLogEntries = 1000
    
    @State private var logSaveURL: URL?
    @State private var logFilename: String = ""

    private let commandHistoryKey = "commandHistory"
    private let logSavePathKey = "logSavePathBookmark"

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    init() {
        _commandHistory = State(initialValue: UserDefaults.standard.stringArray(forKey: commandHistoryKey) ?? [])
        
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

                // UI 모드에 따라 다른 뷰 표시
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
                                    .onTapGesture(count: 2) {
                                        handlePortDoubleClick(port: port)
                                    }
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
                    List {
                        ForEach(commandHistory, id: \.self) { cmd in
                            HStack {
                                Button(action: {
                                    executeCommand(cmd)
                                }) {
                                    Text(cmd)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Button(action: {
                                    removeCommandFromHistory(cmd)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(width: 250)
            .onAppear {
                serialPortManager.findSerialPorts()
                serialPortManager.onDataReceived = { message in
                    DispatchQueue.main.async {
                        let newEntry = LogEntry(timestamp: Date(), message: message)
                        logEntries.append(newEntry)

                        // Limit log entries to prevent performance issues
                        if logEntries.count > maxLogEntries {
                            logEntries.removeFirst(logEntries.count - maxLogEntries)
                        }
                    }
                }
            }
            }

            VStack {
                AutoScrollingTextEditor(
                    text: .constant(logText),
                    font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    shouldAutoScroll: $isAutoScrollEnabled,
                    isPortOpen: serialPortManager.isOpen
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
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            isCommandFieldFocused = true
        }
    }

    func executeCommand(_ commandToExecute: String) {
        let trimmedCommand = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        // Remove existing instances of the command from history
        commandHistory.removeAll { $0 == trimmedCommand }

        // Add the new command to the end of the history
        commandHistory.append(trimmedCommand)

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
        commandHistory.removeAll { $0 == commandToRemove }
        saveCommandHistory()
    }

    func saveCommandHistory() {
        UserDefaults.standard.set(commandHistory, forKey: commandHistoryKey)
    }

    func clearScreen() {
        logEntries.removeAll()
    }

    func handlePortDoubleClick(port: String) {
        // 포트를 선택 상태로 만들기
        serialPortManager.selectedPort = port
        selectedPortLocal = port

        // 해당 포트가 현재 연결된 포트인지 확인
        if serialPortManager.connectedPortPath == port && serialPortManager.isOpen {
            // 이미 열려있는 포트라면 닫기
            serialPortManager.closePort()
        } else {
            // 닫혀있는 포트라면 열기
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
