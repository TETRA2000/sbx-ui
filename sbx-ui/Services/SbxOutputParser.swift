import Foundation

/// Port pattern: matches "8080->3000" or "127.0.0.1:8080->3000/tcp" style port mappings
private nonisolated(unsafe) let portPattern = /(\d+)\s*[-→>]+\s*(\d+)/

enum SbxOutputParser {

    // MARK: - Sandbox List (tabular fallback — prefer JSON via RealSbxService)

    nonisolated static func parseSandboxList(_ stdout: String) -> [Sandbox] {
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

    nonisolated static func parsePolicyList(_ stdout: String) -> [PolicyRule] {
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
    nonisolated static func parsePolicyLog(_ stdout: String) -> [PolicyLogEntry] {
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

    nonisolated static func parsePortsList(_ stdout: String) -> [PortMapping] {
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
