import Foundation

// MARK: - Permission Model

enum PluginPermission: String, Codable, Sendable, CaseIterable {
    case sandboxList = "sandbox.list"
    case sandboxExec = "sandbox.exec"
    case sandboxStop = "sandbox.stop"
    case sandboxRun = "sandbox.run"
    case portsList = "ports.list"
    case portsPublish = "ports.publish"
    case portsUnpublish = "ports.unpublish"
    case envVarList = "envVar.list"
    case envVarSync = "envVar.sync"
    case policyList = "policy.list"
    case policyAllow = "policy.allow"
    case policyDeny = "policy.deny"
    case policyRemove = "policy.remove"
    case fileRead = "file.read"
    case fileWrite = "file.write"
    case uiNotify = "ui.notify"
    case uiLog = "ui.log"

    var displayName: String {
        switch self {
        case .sandboxList: "List sandboxes"
        case .sandboxExec: "Execute commands in sandboxes"
        case .sandboxStop: "Stop sandboxes"
        case .sandboxRun: "Create/resume sandboxes"
        case .portsList: "List port mappings"
        case .portsPublish: "Publish ports"
        case .portsUnpublish: "Unpublish ports"
        case .envVarList: "List environment variables"
        case .envVarSync: "Set environment variables"
        case .policyList: "List network policies"
        case .policyAllow: "Allow network policies"
        case .policyDeny: "Deny network policies"
        case .policyRemove: "Remove network policies"
        case .fileRead: "Read files on host"
        case .fileWrite: "Write files on host"
        case .uiNotify: "Show notifications"
        case .uiLog: "Write to app log"
        }
    }
}

// MARK: - Permission Checker

struct PluginPermissionChecker: Sendable {
    let granted: Set<PluginPermission>

    func check(_ required: PluginPermission) throws {
        guard granted.contains(required) else {
            throw PluginPermissionError.denied(required)
        }
    }

    /// Returns the permission required for a given JSON-RPC method, or nil if no permission is needed.
    static func permissionRequired(for method: String) -> PluginPermission? {
        switch method {
        case "sandbox/list": return .sandboxList
        case "sandbox/exec": return .sandboxExec
        case "sandbox/stop": return .sandboxStop
        case "sandbox/run": return .sandboxRun
        case "sandbox/ports/list": return .portsList
        case "sandbox/ports/publish": return .portsPublish
        case "sandbox/ports/unpublish": return .portsUnpublish
        case "sandbox/envVars/list": return .envVarList
        case "sandbox/envVars/set": return .envVarSync
        case "policy/list": return .policyList
        case "policy/allow": return .policyAllow
        case "policy/deny": return .policyDeny
        case "policy/remove": return .policyRemove
        case "file/read": return .fileRead
        case "file/write": return .fileWrite
        case "ui/notify": return .uiNotify
        case "ui/log": return .uiLog
        default: return nil
        }
    }
}

enum PluginPermissionError: Error, Sendable, LocalizedError {
    case denied(PluginPermission)
    case notApproved(String)

    var errorDescription: String? {
        switch self {
        case .denied(let p): "Permission denied: \(p.rawValue)"
        case .notApproved(let id): "Plugin '\(id)' has not been approved by the user"
        }
    }
}

// MARK: - Approval Persistence

struct PluginApprovalRecord: Codable, Sendable {
    var approvals: [String: PluginApproval]

    struct PluginApproval: Codable, Sendable {
        let permissions: [PluginPermission]
        let approvedAt: Date
    }
}

enum PluginApprovalStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sbx-ui/plugin-approvals.json")
    }

    static func load() -> PluginApprovalRecord {
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(PluginApprovalRecord.self, from: data) else {
            return PluginApprovalRecord(approvals: [:])
        }
        return record
    }

    static func save(_ record: PluginApprovalRecord) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: fileURL, options: .atomic)
    }

    static func isApproved(pluginId: String, permissions: [PluginPermission]) -> Bool {
        let record = load()
        guard let approval = record.approvals[pluginId] else { return false }
        let approvedSet = Set(approval.permissions)
        return Set(permissions).isSubset(of: approvedSet)
    }

    static func approve(pluginId: String, permissions: [PluginPermission]) throws {
        var record = load()
        record.approvals[pluginId] = PluginApprovalRecord.PluginApproval(
            permissions: permissions,
            approvedAt: Date()
        )
        try save(record)
    }

    static func revoke(pluginId: String) throws {
        var record = load()
        record.approvals.removeValue(forKey: pluginId)
        try save(record)
    }
}
