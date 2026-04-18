import Foundation

/// Stateless `FileManager`-backed implementation of `EditorDocumentProvider`.
/// Caller (`EditorStore`) is responsible for scope validation via
/// `EditorPath.validate(_:within:)` before any invocation; the provider
/// trusts the absolute URL it receives.
///
/// Byte-exact round-trip: no trailing-newline insertion, no line-ending
/// rewriting, no encoding transforms. Writes are atomic via `.atomic` option.
public struct DefaultEditorDocumentProvider: EditorDocumentProvider {
    nonisolated public init() {}

    nonisolated public func listDirectory(at path: URL) async throws -> [FileEntry] {
        let url = path.standardizedFileURL
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys
            )
            let entries: [FileEntry] = contents.map { child in
                let values = try? child.resourceValues(forKeys: Set(keys))
                let isDir = values?.isDirectory ?? false
                let size = values?.fileSize.map { Int64($0) }
                let mtime = values?.contentModificationDate
                return FileEntry(
                    url: child.standardizedFileURL,
                    name: child.lastPathComponent,
                    isDirectory: isDir,
                    size: isDir ? nil : size,
                    mtime: mtime
                )
            }
            await Self.log(.info, "listDirectory \(url.path)", detail: "\(entries.count) entries")
            return entries
        } catch {
            await Self.log(.error, "listDirectory failed \(url.path)", detail: (error as NSError).localizedDescription)
            throw error
        }
    }

    nonisolated public func listChangedFiles(in workspaceRoot: URL) async throws -> [ChangedFileEntry] {
        let root = workspaceRoot.standardizedFileURL
        let process = Process()
        process.arguments = ["status", "--porcelain=v1", "-z"]
        // Resolve git via PATH; fall back to /usr/bin/git.
        if let gitURL = Self.resolveGitBinary() {
            process.executableURL = gitURL
        } else {
            await Self.log(.error, "listChangedFiles git not found", detail: root.path)
            throw NSError(
                domain: EditorErrorDomain,
                code: EditorErrorCode.gitUnavailable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: EditorError.gitUnavailable.errorDescription ?? "git unavailable"]
            )
        }
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            await Self.log(.error, "listChangedFiles launch failed \(root.path)", detail: (error as NSError).localizedDescription)
            throw NSError(
                domain: EditorErrorDomain,
                code: EditorErrorCode.gitUnavailable.rawValue,
                userInfo: [NSLocalizedDescriptionKey: EditorError.gitUnavailable.errorDescription ?? "git unavailable"]
            )
        }
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus == 128 {
            await Self.log(.info, "listChangedFiles not a git repo \(root.path)")
            throw NSError(
                domain: EditorErrorDomain,
                code: EditorErrorCode.notGitRepository.rawValue,
                userInfo: [NSLocalizedDescriptionKey: EditorError.notGitRepository.errorDescription ?? "not a git repo"]
            )
        }
        if process.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? "git status failed (exit \(process.terminationStatus))"
            await Self.log(.error, "listChangedFiles \(root.path)", detail: msg)
            throw NSError(
                domain: EditorErrorDomain,
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }

        let entries = Self.parsePorcelain(data: data, root: root)
        await Self.log(.info, "listChangedFiles \(root.path)", detail: "\(entries.count) entries")
        return entries
    }

    nonisolated public func readFile(at path: URL) async throws -> Data {
        let url = path.standardizedFileURL
        do {
            let data = try Data(contentsOf: url)
            await Self.log(.info, "readFile \(url.path)", detail: "\(data.count) bytes")
            return data
        } catch {
            await Self.log(.error, "readFile failed \(url.path)", detail: (error as NSError).localizedDescription)
            throw error
        }
    }

    nonisolated public func writeFile(at path: URL, contents: Data) async throws {
        let url = path.standardizedFileURL
        do {
            try contents.write(to: url, options: [.atomic])
            await Self.log(.info, "writeFile \(url.path)", detail: "\(contents.count) bytes")
        } catch {
            await Self.log(.error, "writeFile failed \(url.path)", detail: (error as NSError).localizedDescription)
            throw error
        }
    }

    nonisolated public func stat(at path: URL) async throws -> FileStat {
        let url = path.standardizedFileURL
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mtime = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
            let typeRaw = attrs[.type] as? FileAttributeType
            let isDir = typeRaw == .typeDirectory
            await Self.log(.info, "stat \(url.path)", detail: "size=\(size) isDir=\(isDir)")
            return FileStat(size: size, mtime: mtime, isDirectory: isDir)
        } catch {
            await Self.log(.error, "stat failed \(url.path)", detail: (error as NSError).localizedDescription)
            throw error
        }
    }

    // MARK: - Logging helper

    @MainActor
    private static func log(_ level: LogStore.Entry.Level, _ message: String, detail: String? = nil) {
        appLog(level, "Editor", message, detail: detail)
    }

    // MARK: - git helpers

    /// Resolves a git binary path by checking a small set of standard locations
    /// and then the user's PATH. Returns nil if no candidate exists.
    nonisolated private static func resolveGitBinary() -> URL? {
        let candidates = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        // Last resort: walk PATH.
        if let env = ProcessInfo.processInfo.environment["PATH"] {
            for dir in env.split(separator: ":") {
                let p = "\(dir)/git"
                if FileManager.default.isExecutableFile(atPath: p) {
                    return URL(fileURLWithPath: p)
                }
            }
        }
        return nil
    }

    /// Parses `git status --porcelain=v1 -z` output into `[ChangedFileEntry]`
    /// sorted alphabetically by relative path.
    /// Format: `XY␠PATH\0` (for rename: `XY␠NEW\0ORIG\0`).
    nonisolated static func parsePorcelain(data: Data, root: URL) -> [ChangedFileEntry] {
        guard let raw = String(data: data, encoding: .utf8) else { return [] }
        let records = raw.split(separator: "\0", omittingEmptySubsequences: true)
        var entries: [ChangedFileEntry] = []
        var i = 0
        while i < records.count {
            let record = records[i]
            guard record.count >= 3 else { i += 1; continue }
            let chars = Array(record)
            let x = chars[0]
            let y = chars[1]
            // chars[2] should be a space per porcelain v1 spec.
            let path = String(chars[3...])
            let changeType = mapChangeType(x: x, y: y)
            if changeType == .renamed {
                // Rename: original path follows in next record.
                i += 1  // skip the "from" entry
            }
            let abs = root.appendingPathComponent(path).standardizedFileURL
            let rel = path
            entries.append(ChangedFileEntry(url: abs, relativePath: rel, changeType: changeType ?? .modified))
            i += 1
        }
        entries.sort { $0.relativePath < $1.relativePath }
        return entries
    }

    nonisolated private static func mapChangeType(x: Character, y: Character) -> GitChangeType? {
        // Untracked is signaled by "??".
        if x == "?" && y == "?" { return .untracked }
        // Prefer the more significant column; index (X) wins over worktree (Y).
        let significant: Character = {
            if x != " " && x != "?" { return x }
            return y
        }()
        switch significant {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .added       // copied — treat like added
        case "T": return .modified    // type change → modified
        case "U": return .modified    // unmerged → modified
        default: return .modified
        }
    }
}
