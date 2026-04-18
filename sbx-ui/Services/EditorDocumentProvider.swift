import Foundation

// MARK: - Provider Protocol

/// Sendable seam through which `EditorStore` performs sandbox-interior file
/// I/O. Errors are raised as `NSError` so the store can surface
/// `localizedDescription` + domain/code directly in a toast. Preconditions
/// for every call: `path` is an absolute URL already validated via
/// `EditorPath.validate(_:within:)`. Implementations trust their caller.
public protocol EditorDocumentProvider: Sendable {
    func listDirectory(at path: URL) async throws -> [FileEntry]
    func readFile(at path: URL) async throws -> Data
    func writeFile(at path: URL, contents: Data) async throws
    func stat(at path: URL) async throws -> FileStat
}

// MARK: - Value Types

public struct FileEntry: Sendable, Hashable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let mtime: Date?

    nonisolated public init(url: URL, name: String, isDirectory: Bool, size: Int64?, mtime: Date?) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.mtime = mtime
    }
}

public struct FileStat: Sendable, Hashable {
    public let size: Int64
    public let mtime: Date
    public let isDirectory: Bool

    nonisolated public init(size: Int64, mtime: Date, isDirectory: Bool) {
        self.size = size
        self.mtime = mtime
        self.isDirectory = isDirectory
    }
}

// MARK: - Error Enum

public enum EditorError: Error, Sendable, LocalizedError {
    case pathOutsideWorkspace(path: URL)
    case fileTooLarge(size: Int64)
    case binaryFile(path: URL)
    case workspaceMissing

    public var errorDescription: String? {
        switch self {
        case .pathOutsideWorkspace(let path):
            "Path is outside the workspace: \(path.path)"
        case .fileTooLarge(let size):
            "File is too large to open: \(size) bytes"
        case .binaryFile(let path):
            "File is not UTF-8 text: \(path.lastPathComponent)"
        case .workspaceMissing:
            "The sandbox workspace directory is missing."
        }
    }
}
