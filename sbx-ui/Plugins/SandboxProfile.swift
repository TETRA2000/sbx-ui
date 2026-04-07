import Foundation

/// Generates macOS sandbox profiles (SBPL) for plugin execution via `sandbox-exec`.
enum SandboxProfile {
    /// Generate an SBPL profile string scoped to the plugin's directory, runtime, and declared permissions.
    static func generate(for manifest: PluginManifest, pluginDirectory: URL, runtimePath: String?) -> String {
        var rules: [String] = []
        let pluginDir = pluginDirectory.standardizedFileURL.path

        // Default deny — block everything not explicitly allowed
        rules.append("(version 1)")
        rules.append("(deny default)")

        // Process execution — restricted to sandbox-exec, the runtime, and the entry script
        if let runtime = runtimePath {
            rules.append("(allow process-exec (literal \"\(escapeSBPL(runtime))\"))")
        }
        let entryPath = pluginDirectory.appendingPathComponent(manifest.entry).standardizedFileURL.path
        rules.append("(allow process-exec (literal \"\(escapeSBPL(entryPath))\"))")
        rules.append("(allow process-exec (literal \"/usr/bin/sandbox-exec\"))")
        // Allow executing common utilities under /usr/bin and /bin (for bash, env, etc.)
        rules.append("(allow process-exec (subpath \"/usr/bin\") (subpath \"/bin\") (subpath \"/usr/sbin\"))")

        // File reads — scoped to plugin dir, runtime paths, system libraries
        rules.append("(allow file-read* (subpath \"\(escapeSBPL(pluginDir))\"))")
        rules.append("(allow file-read* (subpath \"/usr/lib\") (subpath \"/usr/share\") (subpath \"/bin\") (subpath \"/usr/bin\"))")
        rules.append("(allow file-read* (subpath \"/Library/Frameworks\") (subpath \"/System/Library\"))")
        rules.append("(allow file-read* (subpath \"/private/var/db\") (subpath \"/dev\"))")
        rules.append("(allow file-read* (subpath \"/opt/homebrew\") (subpath \"/usr/local\"))")
        // Allow reading the runtime's own directory tree (e.g., Python stdlib, Node modules)
        if let runtime = runtimePath {
            let runtimeDir = (runtime as NSString).deletingLastPathComponent
            rules.append("(allow file-read* (subpath \"\(escapeSBPL(runtimeDir))\"))")
            // Resolve symlinks for runtimes managed by version managers (asdf, pyenv, nvm, etc.)
            if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: runtime) {
                let resolvedDir = (resolved as NSString).deletingLastPathComponent
                rules.append("(allow file-read* (subpath \"\(escapeSBPL(resolvedDir))\"))")
                // Allow the full version manager install tree
                let parentDir = (resolvedDir as NSString).deletingLastPathComponent
                rules.append("(allow file-read* (subpath \"\(escapeSBPL(parentDir))\"))")
            }
        }
        // Allow reading temp dirs (many runtimes need this)
        rules.append("(allow file-read* (subpath \"/private/tmp\") (subpath \"/tmp\"))")

        // Pipe/TTY ioctls for stdin/stdout JSON-RPC communication
        rules.append("(allow file-ioctl)")
        // System info queries (many runtimes need this)
        rules.append("(allow sysctl-read)")
        // Process lifecycle
        rules.append("(allow process-fork)")
        rules.append("(allow signal (target self))")

        // Mach IPC — scoped to common services needed by runtimes
        rules.append("(allow mach-lookup (global-name \"com.apple.system.logger\"))")
        rules.append("(allow mach-lookup (global-name \"com.apple.CoreServices.coreservicesd\"))")
        rules.append("(allow mach-lookup (global-name \"com.apple.SecurityServer\"))")
        rules.append("(allow mach-lookup (global-name \"com.apple.lsd.mapdb\"))")

        // Conditional rules based on declared permissions
        let perms = Set(manifest.permissions)

        if perms.contains(.fileWrite) {
            // Scoped to plugin directory only
            rules.append("(allow file-write* (subpath \"\(escapeSBPL(pluginDir))\"))")
            rules.append("(allow file-write* (subpath \"/private/tmp\") (subpath \"/tmp\"))")
        }

        let networkPerms: Set<PluginPermission> = [
            .policyAllow, .policyDeny, .policyRemove, .policyList,
        ]
        if !perms.isDisjoint(with: networkPerms) {
            rules.append("(allow network*)")
            rules.append("(allow mach-lookup)")  // unrestricted for network-capable plugins
        }

        return rules.joined(separator: "\n")
    }

    /// Escape a path string for safe embedding in SBPL.
    private static func escapeSBPL(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
