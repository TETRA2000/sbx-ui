import Foundation

struct KanbanPersistence {
    let directory: URL

    static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sbx-ui/kanban", isDirectory: true)
    }

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
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

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadBoards() throws -> [KanbanBoard] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.compactMap { url in
            let data = try Data(contentsOf: url)
            return try Self.decoder.decode(KanbanBoard.self, from: data)
        }
    }

    func saveBoard(_ board: KanbanBoard) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(board.id).json")
        let data = try Self.encoder.encode(board)
        try data.write(to: url, options: .atomic)
    }

    func deleteBoard(id: String) throws {
        let url = directory.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
