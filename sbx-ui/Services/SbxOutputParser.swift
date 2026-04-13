import Foundation

/// Port pattern: matches "8080->3000" or "127.0.0.1:8080->3000/tcp" style port mappings
private nonisolated(unsafe) let portPattern = /(\d+)\s*[-→>]+\s*(\d+)/

public enum SbxOutputParser {

    // MARK: - Sandbox List (tabular fallback — prefer JSON via RealSbxService)

    nonisolated public static func parseSandboxList(_ stdout: String) -> [Sandbox] {
        let lines = stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        let header = lines[0]
        // Real CLI uses "SANDBOX" column header (not "NAME")
        guard let nameRange = findColumnRange(header: header, column: "SANDBOX"),
              let agentRange = findColumnRange(header: header, column: "AGENT"),
              let statusRange = findColumnRange(header: header, column: "STATUS"),
              let portsRange = findColumnRange(header: header, column: "PORTS"),
              let workspaceRange = findColumnRange(header: header, column: "WORKSPACE") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let name = extractColumn(line: line, range: nameRange).trimmingCharacters(in: .whitespaces)
            let agent = extractColumn(line: line, range: agentRange).trimmingCharacters(in: .whitespaces)
            let statusStr = extractColumn(line: line, range: statusRange).trimmingCharacters(in: .whitespaces).lowercased()
            let portsStr = extractColumn(line: line, range: portsRange).trimmingCharacters(in: .whitespaces)
            let workspace = extractColumn(line: line, range: workspaceRange).trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty, let status = SandboxStatus(rawValue: statusStr) else {
                return nil
            }

            let ports = parsePortsString(portsStr)

            return Sandbox(
                id: name,
                name: name,
                agent: agent,
                status: status,
                workspace: workspace,
                ports: ports,
                createdAt: Date()
            )
        }
    }

    // MARK: - Policy List (tabular — no JSON option available)

    nonisolated public static func parsePolicyList(_ stdout: String) -> [PolicyRule] {
        // Filter empty lines (real CLI has blank lines between rules)
        let lines = stdout.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return [] }

        let header = lines[0]
        // Real CLI uses "NAME" column header (not "ID")
        guard let idRange = findColumnRange(header: header, column: "NAME"),
              let typeRange = findColumnRange(header: header, column: "TYPE"),
              let decisionRange = findColumnRange(header: header, column: "DECISION"),
              let resourcesRange = findColumnRange(header: header, column: "RESOURCES") else {
            return []
        }

        return lines.dropFirst().compactMap { line in
            let id = extractColumn(line: line, range: idRange).trimmingCharacters(in: .whitespaces)
            let type = extractColumn(line: line, range: typeRange).trimmingCharacters(in: .whitespaces)
            let decisionStr = extractColumn(line: line, range: decisionRange).trimmingCharacters(in: .whitespaces).lowercased()
            let resources = extractColumn(line: line, range: resourcesRange).trimmingCharacters(in: .whitespaces)

            guard !id.isEmpty, let decision = PolicyDecision(rawValue: decisionStr) else {
                return nil
            }

            return PolicyRule(id: id, type: type, decision: decision, resources: resources)
        }
    }

    // MARK: - Policy Log (tabular fallback — prefer JSON via RealSbxService)

    /// Parses policy log output which has "Allowed requests:" and "Blocked requests:" sections.
    nonisolated public static func parsePolicyLog(_ stdout: String) -> [PolicyLogEntry] {
        var results: [PolicyLogEntry] = []
        var currentSection: String? // "allowed" or "blocked"
        var currentHeader: String?

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("Allowed requests:") {
                currentSection = "allowed"
                currentHeader = nil
                continue
            }
            if trimmed.hasPrefix("Blocked requests:") {
                currentSection = "blocked"
                currentHeader = nil
                continue
            }

            // Detect header row
            if trimmed.hasPrefix("SANDBOX") {
                currentHeader = line
                continue
            }

            guard let section = currentSection, let header = currentHeader else { continue }

            // Parse data row using column positions from header
            guard let sandboxRange = findColumnRange(header: header, column: "SANDBOX"),
                  let hostRange = findColumnRange(header: header, column: "HOST"),
                  let proxyRange = findColumnRange(header: header, column: "PROXY"),
                  let ruleRange = findColumnRange(header: header, column: "RULE"),
                  let countRange = findColumnRange(header: header, column: "COUNT") else {
                continue
            }

            let sandbox = extractColumn(line: line, range: sandboxRange).trimmingCharacters(in: .whitespaces)
            let host = extractColumn(line: line, range: hostRange).trimmingCharacters(in: .whitespaces)
            let proxy = extractColumn(line: line, range: proxyRange).trimmingCharacters(in: .whitespaces)
            let rule = extractColumn(line: line, range: ruleRange).trimmingCharacters(in: .whitespaces)
            let countStr = extractColumn(line: line, range: countRange).trimmingCharacters(in: .whitespaces)

            guard !sandbox.isEmpty else { continue }

            results.append(PolicyLogEntry(
                sandbox: sandbox,
                type: "network",
                host: host,
                proxy: proxy,
                rule: rule,
                lastSeen: Date(),
                count: Int(countStr) ?? 0,
                blocked: section == "blocked"
            ))
        }

        return results
    }

    // MARK: - Ports List (tabular fallback — prefer JSON via RealSbxService)

    nonisolated public static func parsePortsList(_ stdout: String) -> [PortMapping] {
        let lines = stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.compactMap { line in
            guard let match = line.firstMatch(of: portPattern),
                  let hostPort = Int(match.1),
                  let sbxPort = Int(match.2) else {
                return nil
            }
            return PortMapping(hostPort: hostPort, sandboxPort: sbxPort, protocolType: "tcp")
        }
    }

    // MARK: - Environment Variables (/etc/sandbox-persistent.sh)

    private static let managedStart = "# --- sbx-ui managed (DO NOT EDIT) ---"
    private static let managedEnd = "# --- end sbx-ui managed ---"

    /// Parse only the sbx-ui managed section from the full file content.
    nonisolated public static func parseManagedEnvVars(_ fileContent: String) -> [EnvVar] {
        let lines = fileContent.components(separatedBy: "\n")
        var inManaged = false
        var result: [EnvVar] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == managedStart {
                inManaged = true
                continue
            }
            if trimmed == managedEnd {
                break
            }
            if inManaged {
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let stripped = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst(7)) : trimmed
                guard let eqIdx = stripped.firstIndex(of: "=") else { continue }
                let key = String(stripped[stripped.startIndex..<eqIdx])
                    .trimmingCharacters(in: .whitespaces)
                let value = String(stripped[stripped.index(after: eqIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                guard SbxValidation.isValidEnvKey(key) else { continue }
                result.append(EnvVar(key: key, value: value))
            }
        }
        return result
    }

    /// Rebuild the full file content: preserve user sections, replace managed section.
    nonisolated public static func rebuildPersistentSh(existingContent: String, managedVars: [EnvVar]) -> String {
        let lines = existingContent.components(separatedBy: "\n")
        var before: [String] = []
        var after: [String] = []
        var inManaged = false
        var foundMarkers = false
        var pastManaged = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == managedStart {
                inManaged = true
                foundMarkers = true
                continue
            }
            if trimmed == managedEnd {
                inManaged = false
                pastManaged = true
                continue
            }
            if inManaged { continue }
            if pastManaged {
                after.append(line)
            } else {
                before.append(line)
            }
        }

        // Build managed block
        var managedBlock: [String] = []
        if !managedVars.isEmpty {
            managedBlock.append(managedStart)
            for v in managedVars {
                managedBlock.append("export \(v.key)=\(v.value)")
            }
            managedBlock.append(managedEnd)
        }

        // Assemble final content
        var parts: [String] = []

        // Before section (trim trailing empty lines if we're adding a managed block)
        var beforeLines = before
        if !managedBlock.isEmpty {
            while let last = beforeLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                beforeLines.removeLast()
            }
        }
        parts.append(contentsOf: beforeLines)

        if !managedBlock.isEmpty {
            // Add separator blank line if there's content before
            if !parts.isEmpty && !(parts.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) {
                parts.append("")
            }
            parts.append(contentsOf: managedBlock)
        }

        if !after.isEmpty {
            // Remove leading empty lines from after section
            var afterLines = after
            while let first = afterLines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
                afterLines.removeFirst()
            }
            if !afterLines.isEmpty {
                if !managedBlock.isEmpty {
                    parts.append("")
                }
                parts.append(contentsOf: afterLines)
            }
        }

        // Ensure trailing newline
        let result = parts.joined(separator: "\n")
        if result.isEmpty { return "" }
        return result.hasSuffix("\n") ? result : result + "\n"
    }

    // MARK: - Private Helpers

    /// Finds the start position of a column header. Returns (start, end) where end
    /// is the start of the next column or Int.max for the last column.
    private nonisolated static func findColumnRange(header: String, column: String) -> (start: Int, end: Int)? {
        guard let range = header.range(of: column) else { return nil }
        let start = header.distance(from: header.startIndex, to: range.lowerBound)
        let afterColumn = header.index(range.upperBound, offsetBy: 0, limitedBy: header.endIndex) ?? header.endIndex
        var nextStart = Int.max
        var i = afterColumn
        var inGap = false
        while i < header.endIndex {
            let c = header[i]
            if c == " " {
                inGap = true
            } else if inGap && c.isUppercase {
                nextStart = header.distance(from: header.startIndex, to: i)
                break
            }
            i = header.index(after: i)
        }
        return (start: start, end: nextStart)
    }

    private nonisolated static func extractColumn(line: String, range: (start: Int, end: Int)) -> String {
        guard range.start < line.count else { return "" }
        let startIdx = line.index(line.startIndex, offsetBy: range.start)
        let endIdx = line.index(line.startIndex, offsetBy: min(range.end, line.count))
        return String(line[startIdx..<endIdx])
    }

    private nonisolated static func parsePortsString(_ portsStr: String) -> [PortMapping] {
        guard !portsStr.isEmpty, portsStr != "-" else { return [] }
        // Real CLI format: "127.0.0.1:8080->3000/tcp, 127.0.0.1:9090->4000/tcp"
        return portsStr.matches(of: portPattern).compactMap { match in
            guard let hostPort = Int(match.1), let sbxPort = Int(match.2) else { return nil }
            return PortMapping(hostPort: hostPort, sandboxPort: sbxPort, protocolType: "tcp")
        }
    }
}
