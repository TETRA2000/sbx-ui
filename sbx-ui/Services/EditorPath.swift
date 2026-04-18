import Foundation

/// Path normalization + scope validation helper. Mirrors the
/// `validatePathScope` pattern used in `PluginApiHandler` — standardizes the
/// candidate URL (without following symlinks) and verifies the resolved
/// path stays inside the workspace root, throwing
/// `EditorError.pathOutsideWorkspace` otherwise.
public enum EditorPath {
    /// Validates that `candidate` resolves to a path equal to or inside `root`.
    /// Does NOT follow symlinks (no `resolvingSymlinksInPath`) — a symlink
    /// whose standardized path falls outside the workspace is rejected.
    public static func validate(_ candidate: URL, within root: URL) throws -> URL {
        let normalizedRoot = root.standardizedFileURL
        let normalizedCandidate = candidate.standardizedFileURL
        let rootPath = normalizedRoot.path
        let candidatePath = normalizedCandidate.path

        if candidatePath == rootPath {
            return normalizedCandidate
        }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(rootPrefix) else {
            throw EditorError.pathOutsideWorkspace(path: normalizedCandidate)
        }
        return normalizedCandidate
    }

    /// Returns the slash-separated path of `absolute` relative to `root`, or
    /// the basename of `absolute` if it is `root` itself or not under `root`.
    public static func relative(_ absolute: URL, to root: URL) -> String {
        let normalizedRoot = root.standardizedFileURL
        let normalizedAbsolute = absolute.standardizedFileURL
        let rootPath = normalizedRoot.path
        let absolutePath = normalizedAbsolute.path
        if absolutePath == rootPath {
            return ""
        }
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if absolutePath.hasPrefix(rootPrefix) {
            return String(absolutePath.dropFirst(rootPrefix.count))
        }
        return normalizedAbsolute.lastPathComponent
    }
}
