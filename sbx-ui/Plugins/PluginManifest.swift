import Foundation

// MARK: - Plugin Manifest

struct PluginManifest: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String
    let entry: String
    let runtime: String?
    let permissions: [PluginPermission]
    let triggers: [PluginTrigger]

    /// The directory containing this plugin's files (set after loading).
    var directory: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, version, description, entry, runtime, permissions, triggers
    }
}

enum PluginTrigger: String, Codable, Sendable {
    case manual
    case onSandboxCreated
    case onSandboxStopped
    case onSandboxRemoved
    case onAppLaunch
}

// MARK: - Loading

enum PluginManifestError: Error, Sendable, LocalizedError {
    case fileNotFound(URL)
    case invalidJson(String)
    case missingField(String)
    case invalidId(String)
    case entryNotFound(String)
    case entryPathTraversal(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url): "plugin.json not found at \(url.path)"
        case .invalidJson(let detail): "Invalid plugin.json: \(detail)"
        case .missingField(let field): "Missing required field: \(field)"
        case .invalidId(let id): "Invalid plugin id '\(id)'. Must be reverse-domain format (e.g. com.example.my-plugin)."
        case .entryNotFound(let path): "Entry file not found: \(path)"
        case .entryPathTraversal(let entry): "Entry '\(entry)' escapes plugin directory. Must be a relative path within the plugin folder."
        }
    }
}

extension PluginManifest {
    /// Load and validate a plugin manifest from a directory containing `plugin.json`.
    static func load(from directory: URL) throws -> PluginManifest {
        let manifestURL = directory.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginManifestError.fileNotFound(manifestURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw PluginManifestError.invalidJson(error.localizedDescription)
        }

        var manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            throw PluginManifestError.invalidJson(error.localizedDescription)
        }

        // Validate required fields
        guard !manifest.id.isEmpty else {
            throw PluginManifestError.missingField("id")
        }
        guard manifest.id.contains(".") else {
            throw PluginManifestError.invalidId(manifest.id)
        }
        guard !manifest.name.isEmpty else {
            throw PluginManifestError.missingField("name")
        }
        guard !manifest.version.isEmpty else {
            throw PluginManifestError.missingField("version")
        }
        guard !manifest.entry.isEmpty else {
            throw PluginManifestError.missingField("entry")
        }

        // Security: reject entry paths that escape the plugin directory
        guard !manifest.entry.contains("..") && !manifest.entry.hasPrefix("/") else {
            throw PluginManifestError.entryPathTraversal(manifest.entry)
        }
        let entryURL = directory.appendingPathComponent(manifest.entry).standardizedFileURL
        let dirPrefix = directory.standardizedFileURL.path + "/"
        guard entryURL.path.hasPrefix(dirPrefix) || entryURL.path == directory.standardizedFileURL.path else {
            throw PluginManifestError.entryPathTraversal(manifest.entry)
        }

        // Validate entry file exists
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            throw PluginManifestError.entryNotFound(entryURL.path)
        }

        manifest.directory = directory
        return manifest
    }
}
