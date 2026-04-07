import Foundation
import os

// MARK: - Plugin Host

/// Manages a single plugin's process lifecycle and bidirectional JSON-RPC communication.
actor PluginHost {
    let manifest: PluginManifest
    let pluginDirectory: URL

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutReadHandle: FileHandle?
    private var pendingRequests: [JsonRpcId: CheckedContinuation<JsonRpcResponse, Error>] = [:]
    private var nextRequestId: Int = 1
    private var apiHandler: PluginApiHandler?

    // Rate limiting
    private var requestTimestamps: [Date] = []
    private let maxRequestsPerSecond: Int = 100

    private let logger = Logger(subsystem: "com.sbx-ui", category: "PluginHost")

    /// Callback invoked on the main actor when the plugin process outputs a log or notification.
    nonisolated let onOutput: @Sendable (String, String) -> Void  // (pluginId, message)
    /// Callback invoked when the plugin process terminates.
    nonisolated let onTerminated: @Sendable (String) -> Void  // (pluginId)

    init(
        manifest: PluginManifest,
        pluginDirectory: URL,
        onOutput: @escaping @Sendable (String, String) -> Void = { _, _ in },
        onTerminated: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.manifest = manifest
        self.pluginDirectory = pluginDirectory
        self.onOutput = onOutput
        self.onTerminated = onTerminated
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Lifecycle

    func start(service: any SbxServiceProtocol) async throws {
        guard process == nil else { return }

        let permissionChecker = PluginPermissionChecker(granted: Set(manifest.permissions))
        apiHandler = PluginApiHandler(service: service, permissionChecker: permissionChecker)

        let proc = Process()
        let entryPath = pluginDirectory.appendingPathComponent(manifest.entry).path
        let sandboxProfile = SandboxProfile.generate(for: manifest)

        if let runtime = manifest.runtime, !runtime.isEmpty {
            let resolvedRuntime = resolveCommand(runtime)
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            proc.arguments = ["-p", sandboxProfile, resolvedRuntime, entryPath]
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            proc.arguments = ["-p", sandboxProfile, entryPath]
        }

        proc.currentDirectoryURL = pluginDirectory

        // Environment: inherit host PATH + plugin context
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        if !currentPath.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(currentPath)"
        }
        env["SBX_PLUGIN_ID"] = manifest.id
        env["SBX_PLUGIN_DIR"] = pluginDirectory.path
        proc.environment = env

        // Bidirectional pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutReadHandle = stdoutPipe.fileHandleForReading

        // Capture stderr for logging
        let pluginId = manifest.id
        let outputCallback = onOutput
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                DispatchQueue.main.async {
                    appLog(.info, "Plugin", "[\(pluginId)] stderr: \(trimmed)")
                    outputCallback(pluginId, trimmed)
                }
            }
        }

        // Process termination handler
        let terminatedCallback = onTerminated
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                appLog(.info, "Plugin", "[\(pluginId)] process terminated")
                terminatedCallback(pluginId)
            }
            Task { [weak self] in
                await self?.handleTermination()
            }
        }

        self.process = proc

        do {
            try proc.run()
            let pid = proc.processIdentifier
            let mid = manifest.id
            DispatchQueue.main.async { appLog(.info, "Plugin", "[\(mid)] started (pid: \(pid))") }
        } catch {
            self.process = nil
            self.stdinHandle = nil
            throw PluginError.launchFailed(manifest.id, error.localizedDescription)
        }

        // Start reading stdout via readabilityHandler (non-blocking, handles pipe closure)
        startReadLoop(stdoutPipe.fileHandleForReading)

        // Send initialize notification
        let initParams: [String: AnyCodable] = [
            "pluginId": .string(manifest.id),
            "version": .string(manifest.version),
        ]
        try sendNotification("initialize", params: initParams)
    }

    func stop() async {
        guard let proc = process, proc.isRunning else {
            cleanup()
            return
        }

        // Graceful shutdown: send notification + close stdin (signals EOF to plugin)
        try? sendNotification("shutdown")
        try? stdinHandle?.close()
        stdinHandle = nil

        // Brief wait for graceful exit
        try? await Task.sleep(for: .milliseconds(500))

        // Force terminate if still alive
        if proc.isRunning {
            proc.terminate()
        }

        // Close stdout to unblock the readLoop
        try? stdoutReadHandle?.close()
        stdoutReadHandle = nil

        cleanup()
    }

    private func cleanup() {
        stdoutReadHandle?.readabilityHandler = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        try? stdoutReadHandle?.close()
        stdoutReadHandle = nil
        process = nil
        apiHandler = nil

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: PluginError.terminated(manifest.id))
        }
        pendingRequests.removeAll()
        requestTimestamps.removeAll()
    }

    private func handleTermination() {
        cleanup()
    }

    // MARK: - Outbound (Host → Plugin)

    func sendNotification(_ method: String, params: [String: AnyCodable]? = nil) throws {
        let notification = JsonRpcNotification(method: method, params: params)
        let data = try JsonRpcCodec.encodeNotification(notification)
        try writeLine(data)
    }

    func sendRequest(_ method: String, params: [String: AnyCodable]? = nil) async throws -> JsonRpcResponse {
        let id = JsonRpcId.int(nextRequestId)
        nextRequestId += 1

        let request = JsonRpcRequest(id: id, method: method, params: params)
        let data = try JsonRpcCodec.encodeRequest(request)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            do {
                try writeLine(data)
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func writeLine(_ data: Data) throws {
        guard let handle = stdinHandle else {
            throw PluginError.notRunning(manifest.id)
        }
        var lineData = data
        lineData.append(contentsOf: [0x0A]) // newline
        try handle.write(contentsOf: lineData)
    }

    // MARK: - Inbound (Plugin → Host)

    /// Starts reading stdout using readabilityHandler — non-blocking and handles pipe closure reliably.
    private nonisolated func startReadLoop(_ handle: FileHandle) {
        var buffer = Data()
        let mid = manifest.id
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                // EOF — process closed stdout
                fileHandle.readabilityHandler = nil
                return
            }
            buffer.append(data)

            // Process complete lines
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = Data(buffer[buffer.startIndex..<newlineIndex])
                buffer = Data(buffer[buffer.index(after: newlineIndex)...])

                if lineData.isEmpty { continue }

                do {
                    let message = try JsonRpcCodec.decode(lineData)
                    Task { [weak self] in
                        await self?.handleIncomingMessage(message)
                    }
                } catch {
                    DispatchQueue.main.async { appLog(.warn, "Plugin", "[\(mid)] failed to decode: \(error)") }
                }
            }
        }
    }

    private func handleIncomingMessage(_ message: JsonRpcMessage) async {
        switch message {
        case .response(let response):
            // Match to pending request
            if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }

        case .request(let request):
            // Plugin is calling a host API method
            let response = await handlePluginRequest(request)
            do {
                let data = try JsonRpcCodec.encodeResponse(response)
                try writeLine(data)
            } catch {
                let mid = self.manifest.id
                DispatchQueue.main.async { appLog(.error, "Plugin", "[\(mid)] failed to send response: \(error)") }
            }

        case .notification(let notification):
            // Plugin-originated notification (e.g., log output)
            if notification.method == "log" {
                let message = notification.params?["message"]?.stringValue ?? ""
                let level = notification.params?["level"]?.stringValue ?? "info"
                let mid = self.manifest.id
                DispatchQueue.main.async { appLog(.info, "Plugin", "[\(mid)] [\(level)] \(message)") }
                onOutput(manifest.id, "[\(level)] \(message)")
            }
        }
    }

    private func handlePluginRequest(_ request: JsonRpcRequest) async -> JsonRpcResponse {
        // Rate limiting
        let now = Date()
        requestTimestamps = requestTimestamps.filter { now.timeIntervalSince($0) < 1.0 }
        if requestTimestamps.count >= maxRequestsPerSecond {
            return JsonRpcResponse.error(
                id: request.id,
                error: JsonRpcError(
                    code: JsonRpcErrorCode.rateLimited,
                    message: "Rate limit exceeded (\(maxRequestsPerSecond) requests/second)"
                )
            )
        }
        requestTimestamps.append(now)

        guard let handler = apiHandler else {
            return JsonRpcResponse.error(
                id: request.id,
                error: JsonRpcError(code: JsonRpcErrorCode.internalError, message: "Plugin not initialized")
            )
        }

        let mid = manifest.id
        DispatchQueue.main.async { appLog(.debug, "Plugin", "[\(mid)] → \(request.method)") }
        return await handler.handle(request: request)
    }

    // MARK: - Command Resolution

    private nonisolated func resolveCommand(_ command: String) -> String {
        if command.hasPrefix("/") { return command }

        let processPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let allPaths = processPath.split(separator: ":").map(String.init) + extraPaths

        for dir in allPaths {
            let fullPath = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return command
    }
}

// MARK: - Plugin Errors

enum PluginError: Error, Sendable, LocalizedError {
    case launchFailed(String, String)
    case notRunning(String)
    case terminated(String)
    case timeout(String)
    case alreadyRunning(String)
    case notFound(String)
    case manifestError(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let id, let reason): "Failed to launch plugin '\(id)': \(reason)"
        case .notRunning(let id): "Plugin '\(id)' is not running"
        case .terminated(let id): "Plugin '\(id)' terminated unexpectedly"
        case .timeout(let id): "Plugin '\(id)' timed out"
        case .alreadyRunning(let id): "Plugin '\(id)' is already running"
        case .notFound(let id): "Plugin '\(id)' not found"
        case .manifestError(let detail): "Plugin manifest error: \(detail)"
        }
    }
}
