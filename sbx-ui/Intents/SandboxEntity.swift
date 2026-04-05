import AppIntents

struct SandboxEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sandbox")
    static var defaultQuery = SandboxEntityQuery()

    var id: String  // sandbox name
    var name: String
    var status: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(status)")
    }
}

struct SandboxEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [SandboxEntity.ID]) async throws -> [SandboxEntity] {
        guard let container = ServiceContainer.shared else { return [] }
        await container.sandboxStore.fetchSandboxes()
        let sandboxes = container.sandboxStore.sandboxes
        return sandboxes
            .filter { identifiers.contains($0.name) }
            .map { SandboxEntity(id: $0.name, name: $0.name, status: $0.status.rawValue) }
    }

    @MainActor
    func suggestedEntities() async throws -> [SandboxEntity] {
        guard let container = ServiceContainer.shared else { return [] }
        await container.sandboxStore.fetchSandboxes()
        let sandboxes = container.sandboxStore.sandboxes
        return sandboxes.map { SandboxEntity(id: $0.name, name: $0.name, status: $0.status.rawValue) }
    }
}
