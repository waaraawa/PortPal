import Foundation
import SwiftUI

class MacroSettings: ObservableObject {
    @Published var commands: [MacroCommand] = []
    @Published var repeatCount: Int = 1
    @Published var isExecuting: Bool = false

    private let macroCommandsKey = "macroCommands"
    private let macroRepeatCountKey = "macroRepeatCount"

    private var executionTask: Task<Void, Never>?

    init() {
        loadSettings()
    }

    func addCommand() {
        commands.append(MacroCommand())
        saveSettings()
    }

    func deleteCommand(at offsets: IndexSet) {
        commands.remove(atOffsets: offsets)
        saveSettings()
    }

    func moveCommand(from source: IndexSet, to destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }

    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(encoded, forKey: macroCommandsKey)
        }
        UserDefaults.standard.set(repeatCount, forKey: macroRepeatCountKey)
    }

    func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: macroCommandsKey),
           let decoded = try? JSONDecoder().decode([MacroCommand].self, from: data) {
            commands = decoded
        }
        repeatCount = UserDefaults.standard.integer(forKey: macroRepeatCountKey)
        if repeatCount == 0 {
            repeatCount = 1
        }
    }

    func startExecution(serialPortManager: SerialPortManager, lineEnding: String) {
        guard !isExecuting else { return }

        isExecuting = true

        executionTask = Task {
            let enabledCommands = commands.filter { $0.isEnabled }

            for iteration in 0..<repeatCount {
                // Check if task was cancelled
                if Task.isCancelled {
                    break
                }

                for (index, command) in enabledCommands.enumerated() {
                    // Check if task was cancelled before each command
                    if Task.isCancelled {
                        break
                    }

                    // Send command
                    await MainActor.run {
                        serialPortManager.send(command.command + lineEnding)
                    }

                    // Apply delay after command (except for the last command in the last iteration)
                    let isLastCommand = (iteration == repeatCount - 1) && (index == enabledCommands.count - 1)
                    if !isLastCommand {
                        try? await Task.sleep(nanoseconds: UInt64(command.delayMs) * 1_000_000)
                    }
                }
            }

            await MainActor.run {
                isExecuting = false
            }
        }
    }

    func stopExecution() {
        executionTask?.cancel()
        executionTask = nil
        isExecuting = false
    }
}
