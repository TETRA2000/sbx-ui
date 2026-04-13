import Foundation

enum KanbanTaskStatus: String, Sendable, Codable {
    case pending
    case blocked
    case creating
    case running
    case completed
    case failed
    case cancelled
}

struct KanbanTask: Identifiable, Sendable, Codable, Equatable {
    let id: String
    var title: String
    var description: String
    var prompt: String
    var columnID: String
    var sortOrder: Int
    var sandboxName: String?
    var dependencyIDs: [String]
    var status: KanbanTaskStatus
    var createdAt: Date
    var completedAt: Date?

    nonisolated init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        prompt: String = "",
        columnID: String,
        sortOrder: Int = 0,
        sandboxName: String? = nil,
        dependencyIDs: [String] = [],
        status: KanbanTaskStatus = .pending,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.prompt = prompt
        self.columnID = columnID
        self.sortOrder = sortOrder
        self.sandboxName = sandboxName
        self.dependencyIDs = dependencyIDs
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

struct KanbanColumn: Identifiable, Sendable, Codable, Equatable {
    let id: String
    var title: String
    var sortOrder: Int
    var isDefault: Bool

    nonisolated init(
        id: String = UUID().uuidString,
        title: String,
        sortOrder: Int,
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.isDefault = isDefault
    }
}

struct KanbanBoard: Identifiable, Sendable, Codable {
    let id: String
    var name: String
    var columns: [KanbanColumn]
    var tasks: [KanbanTask]
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(
        id: String = UUID().uuidString,
        name: String,
        columns: [KanbanColumn]? = nil,
        tasks: [KanbanTask] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.columns = columns ?? KanbanBoard.defaultColumns()
        self.tasks = tasks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated static func defaultColumns() -> [KanbanColumn] {
        [
            KanbanColumn(title: "Backlog", sortOrder: 0, isDefault: true),
            KanbanColumn(title: "In Progress", sortOrder: 1, isDefault: true),
            KanbanColumn(title: "Done", sortOrder: 2, isDefault: true),
        ]
    }

    nonisolated func tasks(inColumn columnID: String) -> [KanbanTask] {
        tasks.filter { $0.columnID == columnID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    nonisolated var sortedColumns: [KanbanColumn] {
        columns.sorted { $0.sortOrder < $1.sortOrder }
    }
}
