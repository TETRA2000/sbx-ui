import Foundation

/// In-memory `EditorDocumentProvider` fixture for unit tests. Stores file
/// contents in a dictionary keyed by absolute path and returns deterministic
/// monotonically advancing `mtime` values so external-change tests can
/// manipulate them explicitly through `setMtime`.
///
/// Mirrors the production contract exactly: methods are `async throws`,
/// errors are `NSError` (or rigged via `fail*` helpers), and path arguments
/// are expected to be absolute (callers are responsible for scope
/// validation).
public actor FakeEditorDocumentProvider: EditorDocumentProvider {
    private var files: [String: Data] = [:]
    private var directories: Set<String> = []
    private var mtimes: [String: Date] = [:]
    private var mtimeCounter: Int = 0

    // Rigging hooks — nil means "succeed normally".
    public var failRead: NSError?
    public var failWrite: NSError?
    public var failStat: NSError?
    public var failList: NSError?
    public var failListChanged: NSError?
    public var readDelay: Duration?
    public var writeDelay: Duration?
    public var listDelay: Duration?
    public var statDelay: Duration?
    public var listChangedDelay: Duration?

    /// Seeded changed-files list returned by `listChangedFiles`.
    private var changedFiles: [ChangedFileEntry] = []

    public init() {}

    // MARK: - Seeding helpers

    public func seedDirectory(_ url: URL) {
        directories.insert(url.standardizedFileURL.path)
        mtimes[url.standardizedFileURL.path] = nextMtime()
    }

    public func seedFile(_ url: URL, contents: Data) {
        files[url.standardizedFileURL.path] = contents
        mtimes[url.standardizedFileURL.path] = nextMtime()
    }

    public func seedFile(_ url: URL, text: String) {
        seedFile(url, contents: Data(text.utf8))
    }

    public func setMtime(_ url: URL, mtime: Date) {
        mtimes[url.standardizedFileURL.path] = mtime
    }

    public func advanceMtime(_ url: URL) {
        mtimes[url.standardizedFileURL.path] = nextMtime()
    }

    public func removeEntry(_ url: URL) {
        let p = url.standardizedFileURL.path
        files.removeValue(forKey: p)
        directories.remove(p)
        mtimes.removeValue(forKey: p)
    }

    public func seedChangedFile(_ entry: ChangedFileEntry) {
        changedFiles.append(entry)
    }

    public func seedChangedFiles(_ entries: [ChangedFileEntry]) {
        changedFiles.append(contentsOf: entries)
    }

    public func resetChangedFiles() {
        changedFiles.removeAll()
    }

    // MARK: - Rigging setters (actor-isolated, callable from tests)

    public func setFailRead(_ error: NSError?) { failRead = error }
    public func setFailWrite(_ error: NSError?) { failWrite = error }
    public func setFailStat(_ error: NSError?) { failStat = error }
    public func setFailList(_ error: NSError?) { failList = error }
    public func setFailListChanged(_ error: NSError?) { failListChanged = error }
    public func setReadDelay(_ delay: Duration?) { readDelay = delay }
    public func setWriteDelay(_ delay: Duration?) { writeDelay = delay }
    public func setListDelay(_ delay: Duration?) { listDelay = delay }
    public func setStatDelay(_ delay: Duration?) { statDelay = delay }
    public func setListChangedDelay(_ delay: Duration?) { listChangedDelay = delay }

    // MARK: - Internal

    private func nextMtime() -> Date {
        mtimeCounter += 1
        return Date(timeIntervalSince1970: TimeInterval(mtimeCounter))
    }

    // MARK: - EditorDocumentProvider

    public func listDirectory(at path: URL) async throws -> [FileEntry] {
        if let delay = listDelay { try? await Task.sleep(for: delay) }
        if let err = failList { throw err }
        let prefix = path.standardizedFileURL.path
        let rootWithSlash = prefix.hasSuffix("/") ? prefix : prefix + "/"
        var entries: [FileEntry] = []

        for p in directories {
            guard p.hasPrefix(rootWithSlash), !p.isEmpty, p != prefix else { continue }
            let rest = String(p.dropFirst(rootWithSlash.count))
            if rest.contains("/") { continue } // not an immediate child
            entries.append(FileEntry(
                url: URL(fileURLWithPath: p),
                name: rest,
                isDirectory: true,
                size: nil,
                mtime: mtimes[p]
            ))
        }
        for (p, data) in files {
            guard p.hasPrefix(rootWithSlash) else { continue }
            let rest = String(p.dropFirst(rootWithSlash.count))
            if rest.contains("/") { continue }
            entries.append(FileEntry(
                url: URL(fileURLWithPath: p),
                name: rest,
                isDirectory: false,
                size: Int64(data.count),
                mtime: mtimes[p]
            ))
        }
        return entries
    }

    public func listChangedFiles(in workspaceRoot: URL) async throws -> [ChangedFileEntry] {
        if let delay = listChangedDelay { try? await Task.sleep(for: delay) }
        if let err = failListChanged { throw err }
        return changedFiles.sorted { $0.relativePath < $1.relativePath }
    }

    public func readFile(at path: URL) async throws -> Data {
        if let delay = readDelay { try? await Task.sleep(for: delay) }
        if let err = failRead { throw err }
        let key = path.standardizedFileURL.path
        guard let data = files[key] else {
            throw NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [NSLocalizedDescriptionKey: "File not found: \(key)"])
        }
        return data
    }

    public func writeFile(at path: URL, contents: Data) async throws {
        if let delay = writeDelay { try? await Task.sleep(for: delay) }
        if let err = failWrite { throw err }
        let key = path.standardizedFileURL.path
        files[key] = contents
        mtimes[key] = nextMtime()
    }

    public func stat(at path: URL) async throws -> FileStat {
        if let delay = statDelay { try? await Task.sleep(for: delay) }
        if let err = failStat { throw err }
        let key = path.standardizedFileURL.path
        if let data = files[key] {
            return FileStat(size: Int64(data.count), mtime: mtimes[key] ?? Date(timeIntervalSince1970: 0), isDirectory: false)
        }
        if directories.contains(key) {
            return FileStat(size: 0, mtime: mtimes[key] ?? Date(timeIntervalSince1970: 0), isDirectory: true)
        }
        throw NSError(domain: NSCocoaErrorDomain, code: 260, userInfo: [NSLocalizedDescriptionKey: "File not found: \(key)"])
    }
}
