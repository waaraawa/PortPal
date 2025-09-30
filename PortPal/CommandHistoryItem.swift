import Foundation

struct CommandHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let command: String
    var usageCount: Int
    var lastUsed: Date

    init(command: String) {
        self.id = UUID()
        self.command = command
        self.usageCount = 1
        self.lastUsed = Date()
    }

    init(id: UUID, command: String, usageCount: Int, lastUsed: Date) {
        self.id = id
        self.command = command
        self.usageCount = usageCount
        self.lastUsed = lastUsed
    }

    mutating func incrementUsage() {
        self.usageCount += 1
        self.lastUsed = Date()
    }

    static func == (lhs: CommandHistoryItem, rhs: CommandHistoryItem) -> Bool {
        return lhs.command == rhs.command
    }
}

enum HistorySortOption: String, CaseIterable, Identifiable {
    case latest = "Latest ↓"
    case usageCount = "Usage Count ↓"

    var id: String { self.rawValue }
}