import Foundation

// MARK: - Plugin API Handler

/// Routes incoming JSON-RPC requests from plugins to `SbxServiceProtocol` methods.
actor PluginApiHandler {
    private let service: any SbxServiceProtocol
    private let permissionChecker: PluginPermissionChecker

    init(service: any SbxServiceProtocol, permissionChecker: PluginPermissionChecker) {
        self.service = service
        self.permissionChecker = permissionChecker
    }

    func handle(request: JsonRpcRequest) async -> JsonRpcResponse {
        // Check permission
        if let required = PluginPermissionChecker.permissionRequired(for: request.method) {
            do {
                try permissionChecker.check(required)
            } catch {
                return JsonRpcResponse.error(
                    id: request.id,
                    error: JsonRpcError(
                        code: JsonRpcErrorCode.permissionDenied,
                        message: "Permission denied: \(required.rawValue)"
                    )
                )
            }
        }

        let params = request.params ?? [:]

        do {
            switch request.method {
            // MARK: Sandbox
            case "sandbox/list":
                return try await handleSandboxList(id: request.id)
            case "sandbox/exec":
                return try await handleSandboxExec(id: request.id, params: params)
            case "sandbox/stop":
                return try await handleSandboxStop(id: request.id, params: params)
            case "sandbox/run":
                return try await handleSandboxRun(id: request.id, params: params)

            // MARK: Ports
            case "sandbox/ports/list":
                return try await handlePortsList(id: request.id, params: params)
            case "sandbox/ports/publish":
                return try await handlePortsPublish(id: request.id, params: params)
            case "sandbox/ports/unpublish":
                return try await handlePortsUnpublish(id: request.id, params: params)

            // MARK: Environment Variables
            case "sandbox/envVars/list":
                return try await handleEnvVarList(id: request.id, params: params)
            case "sandbox/envVars/set":
                return try await handleEnvVarSet(id: request.id, params: params)

            // MARK: Policies
            case "policy/list":
                return try await handlePolicyList(id: request.id)
            case "policy/allow":
                return try await handlePolicyAllow(id: request.id, params: params)
            case "policy/deny":
                return try await handlePolicyDeny(id: request.id, params: params)
            case "policy/remove":
                return try await handlePolicyRemove(id: request.id, params: params)

            // MARK: File I/O
            case "file/read":
                return try handleFileRead(id: request.id, params: params)
            case "file/write":
                return try handleFileWrite(id: request.id, params: params)

            // MARK: UI
            case "ui/notify":
                return handleUiNotify(id: request.id, params: params)
            case "ui/log":
                return handleUiLog(id: request.id, params: params)

            default:
                return JsonRpcResponse.error(
                    id: request.id,
                    error: JsonRpcError(code: JsonRpcErrorCode.methodNotFound, message: "Unknown method: \(request.method)")
                )
            }
        } catch let error as SbxServiceError {
            return JsonRpcResponse.error(
                id: request.id,
                error: JsonRpcError(
                    code: JsonRpcErrorCode.sandboxError,
                    message: error.localizedDescription
                )
            )
        } catch {
            return JsonRpcResponse.error(
                id: request.id,
                error: JsonRpcError(code: JsonRpcErrorCode.internalError, message: error.localizedDescription)
            )
        }
    }

    // MARK: - Sandbox Handlers

    private func handleSandboxList(id: JsonRpcId) async throws -> JsonRpcResponse {
        let sandboxes = try await service.list()
        let result = AnyCodable.array(sandboxes.map { encodeSandbox($0) })
        return .success(id: id, result: result)
    }

    private func handleSandboxExec(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        guard let command = params["command"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: command")
        }
        let args = params["args"]?.arrayValue?.compactMap(\.stringValue) ?? []

        let result = try await service.exec(name: name, command: command, args: args)
        return .success(id: id, result: .object([
            "stdout": .string(result.stdout),
            "stderr": .string(result.stderr),
            "exitCode": .int(Int(result.exitCode)),
        ]))
    }

    private func handleSandboxStop(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        try await service.stop(name: name)
        return .success(id: id, result: .object(["ok": .bool(true)]))
    }

    private func handleSandboxRun(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let agent = params["agent"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: agent")
        }
        guard let workspace = params["workspace"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: workspace")
        }
        let name = params["name"]?.stringValue
        let opts = RunOptions(name: name)
        let sandbox = try await service.run(agent: agent, workspace: workspace, opts: opts)
        return .success(id: id, result: encodeSandbox(sandbox))
    }

    // MARK: - Port Handlers

    private func handlePortsList(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        let ports = try await service.portsList(name: name)
        let result = AnyCodable.array(ports.map { encodePortMapping($0) })
        return .success(id: id, result: result)
    }

    private func handlePortsPublish(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        guard let hostPort = params["hostPort"]?.intValue else {
            return invalidParams(id: id, message: "Missing required param: hostPort")
        }
        guard let sbxPort = params["sbxPort"]?.intValue else {
            return invalidParams(id: id, message: "Missing required param: sbxPort")
        }
        guard (1...65535).contains(hostPort), (1...65535).contains(sbxPort) else {
            return invalidParams(id: id, message: "Port numbers must be between 1 and 65535")
        }
        let mapping = try await service.portsPublish(name: name, hostPort: hostPort, sbxPort: sbxPort)
        return .success(id: id, result: encodePortMapping(mapping))
    }

    private func handlePortsUnpublish(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        guard let hostPort = params["hostPort"]?.intValue else {
            return invalidParams(id: id, message: "Missing required param: hostPort")
        }
        guard let sbxPort = params["sbxPort"]?.intValue else {
            return invalidParams(id: id, message: "Missing required param: sbxPort")
        }
        try await service.portsUnpublish(name: name, hostPort: hostPort, sbxPort: sbxPort)
        return .success(id: id, result: .object(["ok": .bool(true)]))
    }

    // MARK: - Environment Variable Handlers

    private func handleEnvVarList(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        let vars = try await service.envVarList(name: name)
        let result = AnyCodable.array(vars.map { .object(["key": .string($0.key), "value": .string($0.value)]) })
        return .success(id: id, result: result)
    }

    private func handleEnvVarSet(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let name = params["name"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: name")
        }
        guard let key = params["key"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: key")
        }
        guard SbxValidation.isValidEnvKey(key) else {
            return invalidParams(id: id, message: "Invalid environment variable key: \(key)")
        }
        guard let value = params["value"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: value")
        }
        // Fetch current vars, upsert, sync
        var vars = try await service.envVarList(name: name)
        vars.removeAll { $0.key == key }
        vars.append(EnvVar(key: key, value: value))
        try await service.envVarSync(name: name, vars: vars)
        return .success(id: id, result: .object(["ok": .bool(true)]))
    }

    // MARK: - Policy Handlers

    private func handlePolicyList(id: JsonRpcId) async throws -> JsonRpcResponse {
        let rules = try await service.policyList()
        let result = AnyCodable.array(rules.map { encodePolicyRule($0) })
        return .success(id: id, result: result)
    }

    private func handlePolicyAllow(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let resources = params["resources"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: resources")
        }
        let rule = try await service.policyAllow(resources: resources)
        return .success(id: id, result: encodePolicyRule(rule))
    }

    private func handlePolicyDeny(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let resources = params["resources"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: resources")
        }
        let rule = try await service.policyDeny(resources: resources)
        return .success(id: id, result: encodePolicyRule(rule))
    }

    private func handlePolicyRemove(id: JsonRpcId, params: [String: AnyCodable]) async throws -> JsonRpcResponse {
        guard let resource = params["resource"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: resource")
        }
        try await service.policyRemove(resource: resource)
        return .success(id: id, result: .object(["ok": .bool(true)]))
    }

    // MARK: - File I/O Handlers

    private func handleFileRead(id: JsonRpcId, params: [String: AnyCodable]) throws -> JsonRpcResponse {
        guard let path = params["path"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: path")
        }

        // Security: validate path (no traversal)
        let resolved = (path as NSString).standardizingPath
        guard !resolved.contains("..") else {
            return JsonRpcResponse.error(
                id: id,
                error: JsonRpcError(code: JsonRpcErrorCode.permissionDenied, message: "Path traversal not allowed")
            )
        }

        guard FileManager.default.fileExists(atPath: resolved) else {
            return JsonRpcResponse.error(
                id: id,
                error: JsonRpcError(code: JsonRpcErrorCode.sandboxError, message: "File not found: \(resolved)")
            )
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: resolved))
        let content = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        return .success(id: id, result: .object([
            "path": .string(resolved),
            "content": .string(content),
        ]))
    }

    private func handleFileWrite(id: JsonRpcId, params: [String: AnyCodable]) throws -> JsonRpcResponse {
        guard let path = params["path"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: path")
        }
        guard let content = params["content"]?.stringValue else {
            return invalidParams(id: id, message: "Missing required param: content")
        }

        // Security: validate path
        let resolved = (path as NSString).standardizingPath
        guard !resolved.contains("..") else {
            return JsonRpcResponse.error(
                id: id,
                error: JsonRpcError(code: JsonRpcErrorCode.permissionDenied, message: "Path traversal not allowed")
            )
        }

        // Ensure parent directory exists
        let parentDir = (resolved as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        try content.write(toFile: resolved, atomically: true, encoding: .utf8)
        return .success(id: id, result: .object([
            "path": .string(resolved),
            "ok": .bool(true),
        ]))
    }

    // MARK: - UI Handlers

    private func handleUiNotify(id: JsonRpcId, params: [String: AnyCodable]) -> JsonRpcResponse {
        let title = params["title"]?.stringValue ?? "Plugin"
        let message = params["message"]?.stringValue ?? ""
        let level = params["level"]?.stringValue ?? "info"

        DispatchQueue.main.async {
            DispatchQueue.main.async { appLog(.info, "Plugin", "[\(level)] \(title): \(message)") }
        }
        return .success(id: id, result: .object(["ok": .bool(true)]))
    }

    private func handleUiLog(id: JsonRpcId, params: [String: AnyCodable]) -> JsonRpcResponse {
        let message = params["message"]?.stringValue ?? ""
        let level = params["level"]?.stringValue ?? "info"

        DispatchQueue.main.async {
            DispatchQueue.main.async { appLog(.info, "Plugin", "[\(level)] \(message)") }
        }
        return .success(id: id, result: .object(["ok": .bool(true)]))
    }

    // MARK: - Encoding Helpers

    private func encodeSandbox(_ s: Sandbox) -> AnyCodable {
        .object([
            "name": .string(s.name),
            "agent": .string(s.agent),
            "status": .string(s.status.rawValue),
            "workspace": .string(s.workspace),
            "ports": .array(s.ports.map { encodePortMapping($0) }),
        ])
    }

    private func encodePortMapping(_ p: PortMapping) -> AnyCodable {
        .object([
            "hostPort": .int(p.hostPort),
            "sandboxPort": .int(p.sandboxPort),
            "protocolType": .string(p.protocolType),
        ])
    }

    private func encodePolicyRule(_ r: PolicyRule) -> AnyCodable {
        .object([
            "id": .string(r.id),
            "type": .string(r.type),
            "decision": .string(r.decision.rawValue),
            "resources": .string(r.resources),
        ])
    }

    private func invalidParams(id: JsonRpcId, message: String) -> JsonRpcResponse {
        .error(id: id, error: JsonRpcError(code: JsonRpcErrorCode.invalidParams, message: message))
    }
}
