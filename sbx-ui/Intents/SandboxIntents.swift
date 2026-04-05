import AppIntents

struct CreateSandboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Sandbox"
    static var description = IntentDescription("Creates a new Docker sandbox for the given workspace path.")

    @Parameter(title: "Workspace Path")
    var workspacePath: String

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create sandbox at \(\.$workspacePath)") {
            \.$name
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let container = ServiceContainer.shared else {
            throw SbxServiceError.cliError("Service not initialized")
        }
        let sandbox = try await container.sandboxStore.createSandbox(workspace: workspacePath, name: name)
        return .result(value: sandbox.name)
    }
}

struct StopSandboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Sandbox"
    static var description = IntentDescription("Stops a running sandbox.")

    @Parameter(title: "Sandbox")
    var sandbox: SandboxEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Stop \(\.$sandbox)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = ServiceContainer.shared else {
            throw SbxServiceError.cliError("Service not initialized")
        }
        try await container.sandboxStore.stopSandbox(name: sandbox.id)
        return .result()
    }
}

struct ResumeSandboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Sandbox"
    static var description = IntentDescription("Resumes a stopped sandbox. Succeeds silently if already running.")

    @Parameter(title: "Sandbox")
    var sandbox: SandboxEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Resume \(\.$sandbox)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = ServiceContainer.shared else {
            throw SbxServiceError.cliError("Service not initialized")
        }
        // Idempotent: if already running, resumeSandbox will succeed via the stub/real service
        try await container.sandboxStore.resumeSandbox(name: sandbox.id)
        return .result()
    }
}

struct TerminateSandboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Terminate Sandbox"
    static var description = IntentDescription("Permanently removes a sandbox.")

    @Parameter(title: "Sandbox")
    var sandbox: SandboxEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Terminate \(\.$sandbox)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let container = ServiceContainer.shared else {
            throw SbxServiceError.cliError("Service not initialized")
        }
        try await container.sandboxStore.removeSandbox(name: sandbox.id)
        return .result()
    }
}

struct ListSandboxesIntent: AppIntent {
    static var title: LocalizedStringResource = "List Sandboxes"
    static var description = IntentDescription("Returns a list of all sandboxes with their current status.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        guard let container = ServiceContainer.shared else {
            throw SbxServiceError.cliError("Service not initialized")
        }
        await container.sandboxStore.fetchSandboxes()
        let sandboxes = container.sandboxStore.sandboxes
        let result = sandboxes.map { "\($0.name) (\($0.status.rawValue))" }
        return .result(value: result)
    }
}
