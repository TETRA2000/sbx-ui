import AppIntents
import AppKit
import Foundation
import Testing
import UserNotifications
@testable import sbx_ui

// MARK: - MockNotificationCenter

actor MockNotificationCenter: NotificationCenterProtocol {
    var postedRequests: [UNNotificationRequest] = []
    var registeredCategories: Set<UNNotificationCategory> = []
    var authorizationGranted: Bool = true

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationGranted
    }

    func add(_ request: UNNotificationRequest) async throws {
        postedRequests.append(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategories = categories
    }

    func isAuthorized() async -> Bool {
        authorizationGranted
    }

    func setAuthorizationGranted(_ granted: Bool) {
        authorizationGranted = granted
    }
}

// MARK: - NotificationManager Tests

struct NotificationManagerTests {

    // Helper to create a Sandbox with minimal boilerplate
    private func makeSandbox(name: String, status: SandboxStatus) -> Sandbox {
        Sandbox(id: name, name: name, agent: "claude", status: status, workspace: "/tmp/\(name)", ports: [], createdAt: Date())
    }

    /// Wait for the unstructured Task inside postNotification to complete.
    /// Uses Task.yield + Task.sleep to allow main-actor-isolated tasks to run.
    private func waitForPost() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test func requestAuthorizationSetsIsAuthorized() async {
        let mock = MockNotificationCenter()
        await mock.setAuthorizationGranted(true)
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()
        let authorized = await manager.isAuthorized
        #expect(authorized == true)
    }

    @Test func requestAuthorizationDeniedSetsIsAuthorizedFalse() async {
        let mock = MockNotificationCenter()
        await mock.setAuthorizationGranted(false)
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()
        let authorized = await manager.isAuthorized
        #expect(authorized == false)
    }

    @Test func creatingToRunningPostsCreationComplete() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let previous = [makeSandbox(name: "test-sbx", status: .creating)]
        let current = [makeSandbox(name: "test-sbx", status: .running)]
        await manager.onSandboxesUpdated(previous: previous, current: current, busyOperations: [:])

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 1)
        #expect(requests[0].content.title == "Creation Complete")
        #expect(requests[0].content.categoryIdentifier == "sandbox-lifecycle")
    }

    @Test func runningToStoppedPostsUnexpectedStop() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let previous = [makeSandbox(name: "test-sbx", status: .running)]
        let current = [makeSandbox(name: "test-sbx", status: .stopped)]
        await manager.onSandboxesUpdated(previous: previous, current: current, busyOperations: [:])

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 1)
        #expect(requests[0].content.title == "Unexpected Stop")
        #expect(requests[0].content.categoryIdentifier == "sandbox-lifecycle")
    }

    @Test func runningToStoppedWithBusyStoppingSuppressesNotification() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let previous = [makeSandbox(name: "test-sbx", status: .running)]
        let current = [makeSandbox(name: "test-sbx", status: .stopped)]
        let busyOps: [String: SandboxOperation] = ["test-sbx": .stopping]
        await manager.onSandboxesUpdated(previous: previous, current: current, busyOperations: busyOps)

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 0)
    }

    @Test func policyViolationPostsNotification() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        await manager.postPolicyViolation(sandboxName: "test-sbx", blockedHost: "evil.example.com")

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 1)
        #expect(requests[0].content.title == "Policy Violation")
        #expect(requests[0].content.categoryIdentifier == "policy-violation")
    }

    @Test func sessionDisconnectedPostsNotification() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        await manager.postSessionDisconnected(sandboxName: "test-sbx")

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 1)
        #expect(requests[0].content.title == "Session Disconnected")
        #expect(requests[0].content.categoryIdentifier == "session-event")
    }

    @Test func noNotificationsWhenUnauthorized() async {
        let mock = MockNotificationCenter()
        await mock.setAuthorizationGranted(false)
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let authorized = await manager.isAuthorized
        #expect(authorized == false)

        // Try all notification paths — none should post
        let previous = [makeSandbox(name: "test-sbx", status: .creating)]
        let current = [makeSandbox(name: "test-sbx", status: .running)]
        await manager.onSandboxesUpdated(previous: previous, current: current, busyOperations: [:])
        await manager.postPolicyViolation(sandboxName: "test-sbx", blockedHost: "evil.com")
        await manager.postSessionDisconnected(sandboxName: "test-sbx")

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 0)
    }

    @Test func categoriesRegisteredAfterAuthorization() async {
        let mock = MockNotificationCenter()
        // Before authorization, no categories
        let beforeCategories = await mock.registeredCategories
        #expect(beforeCategories.isEmpty)

        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let afterCategories = await mock.registeredCategories
        #expect(afterCategories.count == 3)
        let identifiers = Set(afterCategories.map(\.identifier))
        #expect(identifiers.contains("sandbox-lifecycle"))
        #expect(identifiers.contains("policy-violation"))
        #expect(identifiers.contains("session-event"))
    }

    @Test func threadIdentifierSetPerSandbox() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let previous = [makeSandbox(name: "foo", status: .creating)]
        let current = [makeSandbox(name: "foo", status: .running)]
        await manager.onSandboxesUpdated(previous: previous, current: current, busyOperations: [:])

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 1)
        #expect(requests[0].content.threadIdentifier == "sandbox-foo")
    }

    @Test func noChangeInStatePostsNoNotifications() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let sandboxes = [makeSandbox(name: "test-sbx", status: .running)]
        await manager.onSandboxesUpdated(previous: sandboxes, current: sandboxes, busyOperations: [:])

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 0)
    }

    @Test func multipleTransitionsPostMultipleNotifications() async {
        let mock = MockNotificationCenter()
        let manager = await NotificationManager(center: mock)
        await manager.requestAuthorization()

        let previous = [
            makeSandbox(name: "sbx-a", status: .creating),
            makeSandbox(name: "sbx-b", status: .running),
        ]
        let current = [
            makeSandbox(name: "sbx-a", status: .running),
            makeSandbox(name: "sbx-b", status: .stopped),
        ]
        await manager.onSandboxesUpdated(previous: previous, current: current, busyOperations: [:])

        await waitForPost()

        let requests = await mock.postedRequests
        #expect(requests.count == 2)

        let titles = Set(requests.map(\.content.title))
        #expect(titles.contains("Creation Complete"))
        #expect(titles.contains("Unexpected Stop"))
    }
}

// MARK: - DropHandler Tests

struct DropHandlerTests {

    private func makeSandbox(name: String, status: SandboxStatus, workspace: String) -> Sandbox {
        Sandbox(id: UUID().uuidString, name: name, agent: "claude", status: status, workspace: workspace, ports: [], createdAt: Date())
    }

    @Test func normalizedPathStripsTrailingSlash() {
        let dirNorm: String = DropHandler.normalizedPath(from: URL(fileURLWithPath: "/tmp/my-project", isDirectory: true))
        #expect(dirNorm == "/tmp/my-project")

        let fileNorm: String = DropHandler.normalizedPath(from: URL(fileURLWithPath: "/tmp/my-file.txt", isDirectory: false))
        #expect(fileNorm == "/tmp/my-file.txt")

        let rootNorm: String = DropHandler.normalizedPath(from: URL(fileURLWithPath: "/", isDirectory: true))
        #expect(rootNorm == "/")
    }

    @Test func directoryReturnsTrue() async {
        let coordinator = await NavigationCoordinator()
        let url = URL(fileURLWithPath: "/tmp/my-project", isDirectory: true)
        var showSheet = false
        var droppedPath: String?
        let result: Bool = await DropHandler.handleDroppedURL(
            url, sandboxes: [], coordinator: coordinator,
            showCreateSheet: &showSheet, droppedWorkspacePath: &droppedPath
        )
        #expect(result)
        #expect(showSheet)
        let pathVal: String = droppedPath ?? ""
        #expect(pathVal == "/tmp/my-project")
    }

    @Test func fileReturnsFalse() async {
        let coordinator = await NavigationCoordinator()
        let url = URL(fileURLWithPath: "/tmp/my-file.txt", isDirectory: false)
        var showSheet = false
        var droppedPath: String?
        let result: Bool = await DropHandler.handleDroppedURL(
            url, sandboxes: [], coordinator: coordinator,
            showCreateSheet: &showSheet, droppedWorkspacePath: &droppedPath
        )
        #expect(!result)
        #expect(!showSheet)
        #expect(droppedPath == nil)
    }

    @Test func existingRunningWorkspaceNavigatesToSandbox() async {
        let coordinator = await NavigationCoordinator()
        let sandboxes: [Sandbox] = [
            makeSandbox(name: "claude-project", status: .running, workspace: "/tmp/my-project")
        ]
        let url = URL(fileURLWithPath: "/tmp/my-project", isDirectory: true)
        var showSheet = false
        var droppedPath: String?
        let result: Bool = await DropHandler.handleDroppedURL(
            url, sandboxes: sandboxes, coordinator: coordinator,
            showCreateSheet: &showSheet, droppedWorkspacePath: &droppedPath
        )
        #expect(result)
        #expect(!showSheet)
        #expect(droppedPath == nil)
        let pending: NavigationRequest? = await coordinator.pendingNavigation
        #expect(pending == .sandbox(name: "claude-project"))
    }

    @Test func stoppedSandboxDoesNotNavigate() async {
        let coordinator = await NavigationCoordinator()
        let sandboxes: [Sandbox] = [
            makeSandbox(name: "claude-stopped", status: .stopped, workspace: "/tmp/my-project")
        ]
        let url = URL(fileURLWithPath: "/tmp/my-project", isDirectory: true)
        var showSheet = false
        var droppedPath: String?
        let result: Bool = await DropHandler.handleDroppedURL(
            url, sandboxes: sandboxes, coordinator: coordinator,
            showCreateSheet: &showSheet, droppedWorkspacePath: &droppedPath
        )
        #expect(result)
        #expect(showSheet)
        let pathVal: String = droppedPath ?? ""
        #expect(pathVal == "/tmp/my-project")
        let pending: NavigationRequest? = await coordinator.pendingNavigation
        #expect(pending == nil)
    }

    @Test func multipleItemsUsesFirst() async {
        // handleDrop uses providers.first, so only the first directory is processed.
        // We test the core logic with a single URL representing that first item.
        let coordinator = await NavigationCoordinator()
        let url = URL(fileURLWithPath: "/tmp/first-project", isDirectory: true)
        var showSheet = false
        var droppedPath: String?
        let result: Bool = await DropHandler.handleDroppedURL(
            url, sandboxes: [], coordinator: coordinator,
            showCreateSheet: &showSheet, droppedWorkspacePath: &droppedPath
        )
        #expect(result)
        let pathVal: String = droppedPath ?? ""
        #expect(pathVal == "/tmp/first-project")
    }
}

// MARK: - App Intent Tests (store-level verification, bypasses singleton race)

struct AppIntentTests {

    @Test func createSandboxViaStoreReturnsCorrectName() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        let sandbox = try await store.createSandbox(workspace: "/tmp/project", name: nil)
        #expect(sandbox.name == "claude-project")
    }

    @Test func createSandboxWithCustomName() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        let sandbox = try await store.createSandbox(workspace: "/tmp/project", name: "my-custom")
        #expect(sandbox.name == "my-custom")
    }

    @Test func stopSandboxViaStore() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "stop-test")
        try await store.stopSandbox(name: "stop-test")
        let status = await store.sandboxes.first?.status
        #expect(status == .stopped)
    }

    @Test func stopNonExistentSandboxThrows() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        do {
            try await store.stopSandbox(name: "ghost")
            #expect(Bool(false), "Should have thrown")
        } catch let error as SbxServiceError {
            if case .notFound("ghost") = error {} else {
                #expect(Bool(false), "Wrong error: \(error)")
            }
        }
    }

    @Test func resumeSandboxViaStore() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "resume-test")
        try await store.stopSandbox(name: "resume-test")
        try await store.resumeSandbox(name: "resume-test")
        let status = await store.sandboxes.first?.status
        #expect(status == .running)
    }

    @Test func resumeAlreadyRunningIsIdempotent() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "idempotent-test")
        try await store.resumeSandbox(name: "idempotent-test")
        let status = await store.sandboxes.first?.status
        #expect(status == .running)
    }

    @Test func terminateSandboxViaStore() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "terminate-test")
        try await store.removeSandbox(name: "terminate-test")
        let count = await store.sandboxes.count
        #expect(count == 0)
    }

    @Test func listSandboxesReturnsAll() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/a", name: "alpha")
        _ = try await store.createSandbox(workspace: "/tmp/b", name: "beta")
        await store.fetchSandboxes()
        let sandboxes = await store.sandboxes
        #expect(sandboxes.count == 2)
        let names = sandboxes.map { "\($0.name) (\($0.status.rawValue))" }
        #expect(names.contains("alpha (running)"))
        #expect(names.contains("beta (running)"))
    }

    @Test func listSandboxesEmptyReturnsEmpty() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        await store.fetchSandboxes()
        let sandboxes = await store.sandboxes
        #expect(sandboxes.isEmpty)
    }

    @Test func mutatingOperationRefreshesStore() async throws {
        let service = StubSbxService()
        let store = await SandboxStore(service: service)
        _ = try await store.createSandbox(workspace: "/tmp/project", name: "refresh-test")
        let count = await store.sandboxes.count
        #expect(count == 1)
        try await store.stopSandbox(name: "refresh-test")
        let status = await store.sandboxes.first?.status
        #expect(status == .stopped)
    }
}

// MARK: - SandboxEntity Tests

struct SandboxEntityTests {

    @Test func entityMapsFromSandboxCorrectly() {
        let sandbox = Sandbox(id: "1", name: "entity-a", agent: "claude", status: .running, workspace: "/tmp", ports: [], createdAt: Date())
        let entity = SandboxEntity(id: sandbox.name, name: sandbox.name, status: sandbox.status.rawValue)
        #expect(entity.id == "entity-a")
        #expect(entity.name == "entity-a")
        #expect(entity.status == "running")
    }

    @Test func entityQueryNonExistentReturnsEmpty() async throws {
        await ServiceContainer.configure(service: StubSbxService())
        let query = SandboxEntityQuery()
        let entities = try await query.entities(for: ["nonexistent"])
        #expect(entities.isEmpty)
    }

    @Test func sandboxesToEntitiesMapping() {
        let sandboxes = [
            Sandbox(id: "1", name: "alpha", agent: "claude", status: .running, workspace: "/tmp/a", ports: [], createdAt: Date()),
            Sandbox(id: "2", name: "beta", agent: "claude", status: .stopped, workspace: "/tmp/b", ports: [], createdAt: Date()),
        ]
        let entities = sandboxes.map { SandboxEntity(id: $0.name, name: $0.name, status: $0.status.rawValue) }
        #expect(entities.count == 2)
        #expect(entities[0].name == "alpha")
        #expect(entities[0].status == "running")
        #expect(entities[1].name == "beta")
        #expect(entities[1].status == "stopped")
    }

    @Test func entityDisplayRepresentation() {
        let entity = SandboxEntity(id: "display-test", name: "display-test", status: "running")
        #expect(entity.name == "display-test")
        #expect(entity.status == "running")
        #expect(entity.displayRepresentation.title != nil)
    }
}

// MARK: - SbxShortcutsProvider Tests

struct SbxShortcutsProviderTests {

    @Test func appShortcutsNotEmpty() {
        let shortcuts = SbxShortcutsProvider.appShortcuts
        #expect(!shortcuts.isEmpty)
    }

    @Test func appShortcutsWithinLimit() {
        let shortcuts = SbxShortcutsProvider.appShortcuts
        #expect(shortcuts.count <= 10)
    }
}
