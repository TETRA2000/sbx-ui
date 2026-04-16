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
}
