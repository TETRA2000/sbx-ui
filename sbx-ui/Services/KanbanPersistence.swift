import Foundation

enum KanbanPersistence {
    private static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sbx-ui/kanban", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func loadBoards() throws -> [KanbanBoard] {
        let dir = directory
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            return try decoder.decode(KanbanBoard.self, from: data)
        }
    }

    static func saveBoard(_ board: KanbanBoard) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(board.id).json")
        let data = try encoder.encode(board)
        try data.write(to: url, options: .atomic)
    }

    static func deleteBoard(id: String) throws {
        let url = directory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
