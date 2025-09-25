import SwiftUI

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
            VStack {
                Picker("", selection: $currentUIMode) {
                    ForEach(UIMode.allCases) {
                        mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

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
                        }
                        .disabled(serialPortManager.isOpen)
                        
                        List(selection: $serialPortManager.selectedPort) {
                            ForEach(serialPortManager.serialPorts, id: \.self) { port in
                                Text(port)
                                    .listRowBackground(
                                        (serialPortManager.connectedPortPath == port) ? Color.gray.opacity(0.3) : Color(NSColor.clear)
                                    )
                                    .tag(port)
                            }
                        }
                        
                        HStack {
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
                        .padding(.bottom)
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
                    .padding()
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
                    let newEntry = LogEntry(timestamp: Date(), message: message)
                    logEntries.append(newEntry)
                }
            }

            VStack {
                ScrollViewReader {
                    scrollView in
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(logEntries) {
                                entry in
                                HStack {
                                    Text("[" + dateFormatter.string(from: entry.timestamp) + "]")
                                        .foregroundColor(.gray)
                                    highlightedText(for: entry.message)
                                    Spacer()
                                }
                                .font(.custom("Monaco", size: 11))
                                .padding(.horizontal, 4)
                                .id(entry.id)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .background(Color.white)
                    .onChange(of: logEntries.count) {
                        if let last = logEntries.last {
                            scrollView.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    TextField("Enter command", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .foregroundColor(.primary)
                        .focused($isCommandFieldFocused)
                        .onSubmit {
                            sendFromTextField()
                        }
                    Button("Send") {
                        sendFromTextField()
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            isCommandFieldFocused = true
        }
    }

    private func executeCommand(_ commandToExecute: String) {
        let trimmedCommand = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        // Remove existing instances of the command from history
        commandHistory.removeAll { $0 == trimmedCommand } 
        
        // Add the new command to the end of the history
        commandHistory.append(trimmedCommand)
        
        saveCommandHistory()

        serialPortManager.send(trimmedCommand + "\n")
        isCommandFieldFocused = true
    }

    private func sendFromTextField() {
        executeCommand(command)
        command = ""
    }
    
    private func chooseLogDirectory() {
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
    
    private func startLogging() {
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
    
    private func stopLogging() {
        serialPortManager.stopLiveLogging()
    }
    
    private func generateFilename() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmm"
        if !serialPortManager.isLiveLogging {
            self.logFilename = formatter.string(from: Date()) + ".log"
        }
    }

    private func removeCommandFromHistory(_ commandToRemove: String) {
        commandHistory.removeAll { $0 == commandToRemove }
        saveCommandHistory()
    }

    private func saveCommandHistory() {
        UserDefaults.standard.set(commandHistory, forKey: commandHistoryKey)
    }

    // 하이라이트 텍스트를 생성하는 함수
    private func highlightedText(for message: String) -> Text {
        var result: Text = Text("")
        
        // 정규표현식을 사용하여 모든 키워드를 한 번에 찾음
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
            
            // 키워드 앞의 일반 텍스트 추가
            if range.lowerBound > lastIndex {
                result = result + Text(message[lastIndex..<range.lowerBound])
            }
            
            // 하이라이트된 키워드 추가
            let keywordString = String(message[range])
            if let highlight = keywords.first(where: { $0.keyword == keywordString }) {
                result = result + Text(keywordString).foregroundColor(highlight.swiftUIColor)
            }
            
            lastIndex = range.upperBound
        }
        
        // 마지막 키워드 뒤의 나머지 텍스트 추가
        if lastIndex < message.endIndex {
            result = result + Text(message[lastIndex...])
        }
        
        return result
    }
}
