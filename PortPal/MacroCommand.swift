import Foundation

struct MacroCommand: Identifiable, Codable, Equatable {
    var id = UUID()
    var isEnabled: Bool = true
    var command: String = ""
    var delayMs: Int = 100

    init(id: UUID = UUID(), isEnabled: Bool = true, command: String = "", delayMs: Int = 100) {
        self.id = id
        self.isEnabled = isEnabled
        self.command = command
        self.delayMs = delayMs
    }
}
