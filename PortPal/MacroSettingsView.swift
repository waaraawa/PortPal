import SwiftUI

struct MacroSettingsView: View {
    @ObservedObject var settings: MacroSettings
    @ObservedObject var serialPortManager: SerialPortManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top controls
            VStack(spacing: 6) {
                // Add command button
                Button(action: {
                    settings.addCommand()
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Command")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(settings.isExecuting)

                // Repeat count and Start/Stop button
                HStack(spacing: 8) {
                    Image(systemName: "repeat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", value: $settings.repeatCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                        .disabled(settings.isExecuting)
                        .onChange(of: settings.repeatCount) { _, _ in
                            if settings.repeatCount < 1 {
                                settings.repeatCount = 1
                            }
                            settings.saveSettings()
                        }

                    // Start/Stop execution button
                    if settings.isExecuting {
                        Button(action: {
                            settings.stopExecution()
                        }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundColor(.red)
                                Text("Stop")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(action: {
                            settings.startExecution(
                                serialPortManager: serialPortManager,
                                lineEnding: serialPortManager.lineEnding.stringValue
                            )
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                Text("Start")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!serialPortManager.isOpen || settings.commands.filter { $0.isEnabled }.isEmpty)
                        .help(!serialPortManager.isOpen ? "Port is not open" : settings.commands.filter { $0.isEnabled }.isEmpty ? "No enabled commands" : "Start macro execution")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Divider()

            // Command blocks list
            List {
                ForEach($settings.commands) { $command in
                    MacroCommandRow(command: $command, isExecuting: settings.isExecuting) {
                        if let index = settings.commands.firstIndex(where: { $0.id == command.id }) {
                            settings.commands.remove(at: index)
                            settings.saveSettings()
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .onMove { source, destination in
                    settings.moveCommand(from: source, to: destination)
                }
            }
            .listStyle(.plain)
            .disabled(settings.isExecuting)
        }
    }
}

struct MacroCommandRow: View {
    @Binding var command: MacroCommand
    let isExecuting: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            // Enable/Disable checkbox
            Button(action: {
                command.isEnabled.toggle()
            }) {
                Image(systemName: command.isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundColor(command.isEnabled ? .blue : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .disabled(isExecuting)
            .help("Enable/Disable")

            // Command input
            TextField("Command", text: $command.command)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .disabled(isExecuting)

            // Delay input
            TextField("100", value: $command.delayMs, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .disabled(isExecuting)
                .help("Delay (ms)")

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .disabled(isExecuting)
            .help("Delete")
        }
        .padding(.vertical, 2)
    }
}
