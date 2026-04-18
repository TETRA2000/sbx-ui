import Foundation

// MARK: - Provider Protocol

/// Sendable seam through which `EditorStore` performs sandbox-interior file
/// I/O. Errors are raised as `NSError` so the store can surface
/// `localizedDescription` + domain/code directly in a toast. Preconditions
/// for every call: `path` is an absolute URL already validated via
/// `EditorPath.validate(_:within:)`. Implementations trust their caller.
public protocol EditorDocumentProvider: Sendable {
    func listDirectory(at path: URL) async throws -> [FileEntry]
    func listChangedFiles(in workspaceRoot: URL) async throws -> [ChangedFileEntry]
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

/// A file with uncommitted changes detected by `git status`.
public struct ChangedFileEntry: Sendable, Hashable, Identifiable {
    public var id: String { relativePath }
    public let url: URL              // absolute path under workspace root
    public let relativePath: String  // path relative to workspace root
    public let changeType: GitChangeType

    nonisolated public init(url: URL, relativePath: String, changeType: GitChangeType) {
        self.url = url
        self.relativePath = relativePath
        self.changeType = changeType
    }
}

/// Git status change kind. Raw value is the one-character badge label.
public enum GitChangeType: String, Sendable, Hashable, CaseIterable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "U"
}

// MARK: - Error Enum

public enum EditorError: Error, Sendable, LocalizedError {
    case pathOutsideWorkspace(path: URL)
    case fileTooLarge(size: Int64)
    case binaryFile(path: URL)
    case workspaceMissing
    case notGitRepository
    case gitUnavailable

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
        case .notGitRepository:
            "Not a git repository."
        case .gitUnavailable:
            "git is not available on this system."
        }
    }
}

// MARK: - NSError bridging

/// Domain used when the provider throws git-related errors as NSError so
/// the store can distinguish them from generic filesystem errors.
public nonisolated let EditorErrorDomain = "EditorError"

public enum EditorErrorCode: Int, Sendable {
    case notGitRepository = 2001
    case gitUnavailable = 2002
}
