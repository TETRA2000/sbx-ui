import Foundation

/// Generates macOS sandbox profiles (SBPL) for plugin execution via `sandbox-exec`.
enum SandboxProfile {
    /// Generate an SBPL profile string based on the plugin's declared permissions.
    static func generate(for manifest: PluginManifest) -> String {
        var rules: [String] = []

        // Default deny — block everything not explicitly allowed
        rules.append("(version 1)")
        rules.append("(deny default)")

        // Base rules required for any plugin to function:
        // Execute processes (the runtime + script)
        rules.append("(allow process-exec*)")
        // Read files (runtime binaries, shared libs, plugin dir, /dev/null, etc.)
        rules.append("(allow file-read*)")
        // Pipe/TTY ioctls for stdin/stdout JSON-RPC communication
        rules.append("(allow file-ioctl)")
        // System info queries (many runtimes need this)
        rules.append("(allow sysctl-read)")
        // Mach IPC (needed by bash, python, node, and most runtimes)
        rules.append("(allow mach-lookup)")
        // Process lifecycle
        rules.append("(allow process-fork)")
        rules.append("(allow signal (target self))")

        // Conditional rules based on declared permissions
        let perms = Set(manifest.permissions)

        if perms.contains(.fileWrite) {
            rules.append("(allow file-write*)")
        }

        let networkPerms: Set<PluginPermission> = [
            .policyAllow, .policyDeny, .policyRemove, .policyList,
        ]
        if !perms.isDisjoint(with: networkPerms) {
            rules.append("(allow network*)")
        }

        return rules.joined(separator: "\n")
    }
}
