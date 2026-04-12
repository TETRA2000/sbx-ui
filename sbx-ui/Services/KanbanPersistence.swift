import Foundation

struct KanbanPersistence: Sendable {
    let directory: URL

    nonisolated static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sbx-ui/kanban", isDirectory: true)
    }

    nonisolated init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    nonisolated private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    nonisolated private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    nonisolated func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated func loadBoards() throws -> [KanbanBoard] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(KanbanBoard.self, from: data)
        }
    }

    nonisolated func saveBoard(_ board: KanbanBoard) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(board.id).json")
        let data = try Self.encoder.encode(board)
        try data.write(to: url, options: .atomic)
    }

    nonisolated func deleteBoard(id: String) throws {
        let url = directory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
