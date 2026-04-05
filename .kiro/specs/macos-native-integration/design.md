# Design Document

## Overview

**Purpose**: This feature delivers five macOS platform integrations — Menu Bar Extra, system notifications, drag & drop, dock menu, and App Intents — to sbx-ui users who manage Docker Sandbox lifecycles.

**Users**: Individual developers use sbx-ui alongside other macOS tools. These integrations let them monitor sandbox status, receive alerts, and trigger operations from the menu bar, dock, Finder, Shortcuts, and Siri — without switching to the main app window.

**Impact**: Modifies the App entry point to add new Scenes (MenuBarExtra) and an NSApplicationDelegateAdaptor. Introduces a ServiceContainer singleton to share state between the SwiftUI view hierarchy and external entry points (App Intents, dock menu, notifications). Adds a NavigationCoordinator for cross-feature deep linking.

### Goals
- Persistent system-level sandbox monitoring via menu bar icon with running count
- Proactive lifecycle alerts (creation complete, unexpected stop, policy violations, session disconnect)
- Frictionless sandbox creation by dropping folders from Finder
- Quick sandbox actions from the dock right-click menu
- Full Shortcuts/Siri automation for sandbox CRUD operations

### Non-Goals
- Touch Bar support (deprecated hardware)
- Global keyboard shortcuts (separate feature)
- Launch at Login / SMAppService (separate feature)
- Spotlight/CoreSpotlight indexing (separate feature)
- Menu bar icon customization or theming
- Notification sound/badge customization UI within the app

## Architecture

### Existing Architecture Analysis

The app follows a three-layer architecture: Service → Store → View.

- **Service layer**: `SbxServiceProtocol` (actor) wraps the `sbx` CLI. `ServiceFactory.create()` returns the concrete implementation.
- **Store layer**: `@MainActor @Observable` classes (`SandboxStore`, `PolicyStore`, `TerminalSessionStore`) hold state and call services. Created in `App.init()` and injected via `.environment()`.
- **View layer**: SwiftUI views read stores from the environment. Navigation state lives in `ShellView` as `@State` (`selection: SidebarDestination?`, `selectedSessionID: String?`).
- **Entry point**: Single `WindowGroup` scene. No `@NSApplicationDelegateAdaptor`.

Key constraint: Stores are `@MainActor`-isolated. Any new component accessing stores (AppDelegate, App Intents) must dispatch to MainActor.

### Architecture Pattern & Boundary Map

Selected pattern: **ServiceContainer singleton** — centralizes store instances so they are accessible from both the SwiftUI environment and external entry points (App Intents, AppDelegate).

```mermaid
graph TB
    subgraph AppEntry
        AppStruct[sbx_uiApp]
        WG[WindowGroup]
        MBE[MenuBarExtra]
    end

    subgraph AppKit Bridge
        AD[AppDelegate]
        DM[Dock Menu Builder]
        ND[Notification Delegate]
    end

    subgraph SharedState
        SC[ServiceContainer]
        SS[SandboxStore]
        PS[PolicyStore]
        NC[NavigationCoordinator]
        NM[NotificationManager]
    end

    subgraph Intents
        CI[CreateSandboxIntent]
        SI[StopSandboxIntent]
        RI[ResumeSandboxIntent]
        TI[TerminateSandboxIntent]
        LI[ListSandboxesIntent]
    end

    subgraph Views
        SV[ShellView]
        DV[DashboardView]
    end

    AppStruct --> SC
    AppStruct --> WG
    AppStruct --> MBE
    AppStruct --> AD

    SC --> SS
    SC --> PS
    SC --> NC
    SC --> NM

    AD --> DM
    AD --> ND
    AD --> SC

    DM --> SS
    ND --> NC
    NM --> SS

    CI --> SC
    SI --> SC
    RI --> SC
    TI --> SC
    LI --> SC

    WG --> SV
    SV --> DV
    SV --> NC

    MBE --> SS
    MBE --> NC
```

**Architecture Integration**:
- Existing patterns preserved: Protocol-based services, @MainActor @Observable stores, environment injection for views
- New components: ServiceContainer (shared singleton), NavigationCoordinator (deep linking), NotificationManager (UNUserNotificationCenter wrapper), AppDelegate (dock menu + notification delegate)
- Domain boundaries: Each of the 5 features is a self-contained module (view/intent/delegate method) that interacts with shared state only through stores and coordinators

### Technology Stack

| Layer | Choice / Version | Role in Feature | Notes |
|-------|------------------|-----------------|-------|
| UI | SwiftUI MenuBarExtra (macOS 13+) | Menu bar popover scene | `.menuBarExtraStyle(.window)` |
| UI | SwiftUI onDrop / DropDelegate | Drag & drop on dashboard | UTType.fileURL |
| AppKit Bridge | @NSApplicationDelegateAdaptor | Dock menu + notification delegate | Single AppDelegate class |
| Notifications | UserNotifications (UNUserNotificationCenter) | Post and handle system notifications | macOS banner style default |
| Automation | App Intents (macOS 13+) | Shortcuts/Siri integration | AppIntent, AppEntity, AppShortcutsProvider |
| Types | UniformTypeIdentifiers | Drop validation | UTType.fileURL |

## System Flows

### Notification Lifecycle (State Diffing)

```mermaid
sequenceDiagram
    participant Poll as SandboxStore Polling
    participant NM as NotificationManager
    participant UN as UNUserNotificationCenter
    participant User as User

    Poll->>NM: onSandboxesUpdated(old, new)
    NM->>NM: Diff old vs new statuses
    alt Creating to Running
        NM->>UN: Post Creation Complete
    else Running to Stopped AND not user-initiated
        NM->>NM: Check busyOperations for stopping
        NM->>UN: Post Unexpected Stop
    end
    UN->>User: Display banner notification
    User->>UN: Click notification
    UN->>NM: didReceive response
    NM->>NM: Parse category and sandbox name
    NM->>NM: Set NavigationCoordinator.pendingNavigation
```

### App Intent Execution

```mermaid
sequenceDiagram
    participant SC as Shortcuts / Siri
    participant Intent as StopSandboxIntent
    participant Container as ServiceContainer
    participant Store as SandboxStore

    SC->>Intent: perform()
    Intent->>Container: resolve shared instance
    Intent->>Store: stopSandbox(name)
    Store->>Store: fetchSandboxes()
    Store-->>Intent: success
    Intent-->>SC: IntentResult.result()
```

## Requirements Traceability

| Requirement | Summary | Components | Interfaces | Flows |
|-------------|---------|------------|------------|-------|
| 1.1–1.3 | Menu bar icon with running count | MenuBarPopoverView, ServiceContainer | SandboxStore.sandboxes | — |
| 1.4–1.8 | Menu bar sandbox list and actions | MenuBarPopoverView | SandboxStore.stop/resume | — |
| 1.9–1.10 | Menu bar navigation and create | MenuBarPopoverView, NavigationCoordinator | NavigationCoordinator.navigate() | — |
| 1.11 | Quit action | MenuBarPopoverView | NSApplication.terminate | — |
| 1.12 | Shared polling data | ServiceContainer | SandboxStore (shared instance) | — |
| 2.1–2.4 | Notification posting for events | NotificationManager | NotificationManager.post() | Notification Lifecycle |
| 2.5–2.6 | Notification click navigation | AppDelegate (UNDelegate), NavigationCoordinator | NavigationCoordinator.navigate() | Notification Lifecycle |
| 2.7–2.8 | Notification authorization | NotificationManager | UNUserNotificationCenter.requestAuthorization | — |
| 2.9 | Notification categories | NotificationManager | UNNotificationCategory registration | — |
| 2.10 | Suppress user-initiated stop | NotificationManager | SandboxStore.busyOperations | Notification Lifecycle |
| 3.1, 3.5 | Drop zone overlay | DashboardView (onDrop modifier) | isTargeted binding | — |
| 3.2, 3.6 | Drop to create | DashboardView, DropZoneOverlay | CreateProjectSheet pre-fill | — |
| 3.3–3.4 | Drop validation | DashboardView (DropDelegate) | FileManager directory check | — |
| 3.7 | Drop existing workspace | DashboardView | NavigationCoordinator.navigate() | — |
| 4.1–4.2 | Dock menu sandbox list | AppDelegate, DockMenuBuilder | SandboxStore.sandboxes | — |
| 4.3–4.7 | Dock menu actions | AppDelegate, DockMenuBuilder | SandboxStore.stop/resume, NavigationCoordinator | — |
| 4.8–4.10 | Dock menu new sandbox and rebuild | AppDelegate, DockMenuBuilder | NavigationCoordinator.navigate() | — |
| 5.1–5.6 | Sandbox CRUD intents | CreateSandboxIntent, StopSandboxIntent, ResumeSandboxIntent, TerminateSandboxIntent, ListSandboxesIntent | ServiceContainer, SandboxStore | App Intent Execution |
| 5.7–5.8 | Intent error handling and idempotency | All intent structs | SbxServiceError mapping | — |
| 5.9 | Siri phrases | SbxShortcutsProvider | AppShortcutsProvider protocol | — |
| 5.10 | Intent parameter metadata | All intent structs | @Parameter annotations | — |
| 5.11 | Intent triggers refresh | All mutating intents | SandboxStore.fetchSandboxes() | App Intent Execution |
| 5.12 | Dynamic sandbox picker | SandboxEntity, SandboxEntityQuery | DynamicOptionsProvider, EntityQuery | — |

## Components and Interfaces

| Component | Domain/Layer | Intent | Req Coverage | Key Dependencies | Contracts |
|-----------|-------------|--------|--------------|------------------|-----------|
| ServiceContainer | Infrastructure | Shared singleton holding stores and services | All | SbxServiceProtocol (P0) | State |
| NavigationCoordinator | Infrastructure | Centralized deep-link navigation | 1.9, 1.10, 2.5, 2.6, 3.7, 4.7, 4.8 | — | State |
| NotificationManager | Service | Post and manage macOS notifications | 2.1–2.10 | UNUserNotificationCenter (P0), SandboxStore (P0) | Service, Event |
| AppDelegate | AppKit Bridge | Dock menu builder + notification delegate | 2.5, 2.6, 4.1–4.10 | ServiceContainer (P0) | Service |
| MenuBarPopoverView | UI | Menu bar popover with sandbox list | 1.1–1.12 | SandboxStore (P0), NavigationCoordinator (P1) | — |
| DropZoneOverlay | UI | Visual feedback for drag & drop | 3.1, 3.5 | — | — |
| DashboardView (modified) | UI | Adds onDrop handler and drop zone | 3.1–3.7 | SandboxStore (P0), NavigationCoordinator (P1) | — |
| SandboxEntity | App Intents | AppEntity representation of a sandbox | 5.12 | ServiceContainer (P0) | State |
| CreateSandboxIntent | App Intents | Shortcuts intent for creating sandboxes | 5.1, 5.6, 5.10, 5.11 | ServiceContainer (P0) | Service |
| StopSandboxIntent | App Intents | Shortcuts intent for stopping sandboxes | 5.2, 5.7, 5.10, 5.11 | ServiceContainer (P0) | Service |
| ResumeSandboxIntent | App Intents | Shortcuts intent for resuming sandboxes | 5.3, 5.8, 5.10, 5.11 | ServiceContainer (P0) | Service |
| TerminateSandboxIntent | App Intents | Shortcuts intent for terminating sandboxes | 5.4, 5.10, 5.11 | ServiceContainer (P0) | Service |
| ListSandboxesIntent | App Intents | Shortcuts intent for listing sandboxes | 5.5, 5.10 | ServiceContainer (P0) | Service |
| SbxShortcutsProvider | App Intents | Siri phrase registration | 5.9 | All intents (P0) | — |

### Infrastructure Layer

#### ServiceContainer

| Field | Detail |
|-------|--------|
| Intent | Shared singleton holding canonical instances of services and stores |
| Requirements | All (enables access from App Intents, AppDelegate, and SwiftUI) |

**Responsibilities & Constraints**
- Owns the single `SbxServiceProtocol` instance and all store instances
- Created once at app startup; accessed via `ServiceContainer.shared`
- Thread-safe: stores are `@MainActor`, container provides access to them

**Dependencies**
- External: SbxServiceProtocol — CLI executor (P0)

**Contracts**: State [x]

##### State Management
- State model: `shared` static property holding `service`, `sandboxStore`, `policyStore`, `sessionStore`, `navigationCoordinator`, `notificationManager`
- Persistence: In-memory only (stores are ephemeral, rebuilt on app launch)
- Concurrency: Container itself is `@MainActor`; all property access is MainActor-isolated

```swift
@MainActor
final class ServiceContainer {
    private(set) static var shared = ServiceContainer()

    let service: any SbxServiceProtocol
    let sandboxStore: SandboxStore
    let policyStore: PolicyStore
    let sessionStore: TerminalSessionStore
    let navigationCoordinator: NavigationCoordinator
    let notificationManager: NotificationManager

    /// Test-only: replace the shared container with one backed by a stub service.
    static func configure(service: any SbxServiceProtocol) {
        shared = ServiceContainer(service: service)
    }
}
```

**Implementation Notes**
- Integration: `sbx_uiApp.init()` initializes `ServiceContainer.shared`, then reads stores from it for `@State` and `.environment()` injection. In tests, `ServiceContainer.configure(service: StubSbxService())` is called in setUp to inject a stub.
- Validation: ServiceFactory.create() is called once inside the default initializer
- Risks: Singleton introduces global state; mitigated by `configure(service:)` for test injection

#### NavigationCoordinator

| Field | Detail |
|-------|--------|
| Intent | Centralized deep-link handler for cross-feature navigation requests |
| Requirements | 1.9, 1.10, 2.5, 2.6, 3.7, 4.7, 4.8 |

**Responsibilities & Constraints**
- Receives navigation requests from menu bar, dock menu, notifications, and intents
- Publishes a `pendingNavigation` that ShellView observes and executes
- Manages window activation (bring main window to front)

**Contracts**: State [x]

##### State Management

```swift
enum NavigationRequest: Equatable {
    case sandbox(name: String)           // open sandbox session
    case policyLog(sandboxName: String)  // open policy log filtered to sandbox
    case createSheet                     // open create sandbox sheet
    case createWithWorkspace(path: String) // open create sheet with workspace pre-filled
}

@MainActor @Observable
final class NavigationCoordinator {
    var pendingNavigation: NavigationRequest?

    func navigate(to request: NavigationRequest)
    func activateMainWindow()
    func consumeNavigation() -> NavigationRequest?
}
```

- `navigate(to:)` sets `pendingNavigation` and calls `activateMainWindow()`
- `activateMainWindow()` uses `NSApplication.shared.activate()` and orders front the key window
- ShellView calls `consumeNavigation()` in an `.onChange(of:)` to handle the request and clear it

### Service Layer

#### NotificationManager

| Field | Detail |
|-------|--------|
| Intent | Wraps UNUserNotificationCenter for posting and managing sandbox lifecycle notifications |
| Requirements | 2.1–2.10 |

**Responsibilities & Constraints**
- Requests notification authorization on initialization
- Posts notifications for lifecycle transitions, policy violations, session disconnects
- Defines notification categories with action buttons
- Checks `SandboxStore.busyOperations` before posting "unexpected stop" to suppress user-initiated stops
- Tracks previously seen sandbox states to detect transitions

**Dependencies**
- External: UNUserNotificationCenter (P0)
- Inbound: SandboxStore — provides sandbox state and busyOperations (P0)
- Outbound: NavigationCoordinator — receives navigation requests from notification clicks (P1)

**Contracts**: Service [x] / Event [x]

##### Service Interface

```swift
@MainActor @Observable
final class NotificationManager {
    private(set) var isAuthorized: Bool

    func requestAuthorization() async
    func onSandboxesUpdated(previous: [Sandbox], current: [Sandbox], busyOperations: [String: SandboxOperation])
    func postPolicyViolation(sandboxName: String, blockedHost: String)
    func postSessionDisconnected(sandboxName: String)
}
```

- Preconditions: `requestAuthorization()` called before any posting
- Postconditions: Notification posted only if `isAuthorized == true`
- Invariants: User-initiated stops (busyOperations contains `.stopping`) never trigger "unexpected stop" notifications

##### Event Contract
- Published events: UNNotification posts with categories `sandbox-lifecycle`, `policy-violation`, `session-event`
- Subscribed events: UNUserNotificationCenterDelegate `didReceive` response (handled by AppDelegate, forwarded to NavigationCoordinator)

##### Notification Categories

| Category ID | Actions | Thread Grouping |
|-------------|---------|-----------------|
| `sandbox-lifecycle` | "Open" (foreground) | `sandbox-{name}` |
| `policy-violation` | "View Log" (foreground) | `policy-{sandboxName}` |
| `session-event` | "Reconnect" (foreground) | `session-{sandboxName}` |

**Implementation Notes**
- Integration: State diffing is driven by SwiftUI observation, NOT by modifying SandboxStore. The App body (or ShellView) uses `.onChange(of: sandboxStore.sandboxes)` to detect state transitions, captures the previous value, and calls `notificationManager.onSandboxesUpdated(previous:current:busyOperations:)`. This keeps SandboxStore decoupled from the notification system.
- Validation: Only posts if authorization granted and category matches a known transition
- Risks: macOS defaults to banner (not alert) — notifications may be missed. No mitigation within app; user must configure in System Settings.

### AppKit Bridge Layer

#### AppDelegate

| Field | Detail |
|-------|--------|
| Intent | NSApplicationDelegate providing dock menu and notification delegate |
| Requirements | 2.5, 2.6, 4.1–4.10 |

**Responsibilities & Constraints**
- Implements `applicationDockMenu(_:)` — builds NSMenu from current SandboxStore state on each invocation
- Conforms to `UNUserNotificationCenterDelegate` — handles notification click responses
- Accesses stores via `ServiceContainer.shared`
- Sets itself as UNUserNotificationCenter delegate in `applicationDidFinishLaunching`

**Dependencies**
- Inbound: NSApplication — dock menu callback, launch callback (P0)
- Inbound: UNUserNotificationCenter — notification response callback (P0)
- Outbound: ServiceContainer — store access (P0)
- Outbound: NavigationCoordinator — deep link execution (P1)

**Contracts**: Service [x]

##### Service Interface

```swift
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu?
    func applicationDidFinishLaunching(_ notification: Notification)
    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler: @escaping () -> Void)
}
```

##### Dock Menu Construction

`applicationDockMenu(_:)` rebuilds the menu each invocation:
1. "New Sandbox…" item at top
2. Separator
3. Running sandboxes (submenu: Stop, Open)
4. Stopped sandboxes (submenu: Resume, Open)

Action selectors dispatch to MainActor and call `SandboxStore.stopSandbox/resumeSandbox` or `NavigationCoordinator.navigate(to:)`.

**Implementation Notes**
- Integration: Registered via `@NSApplicationDelegateAdaptor(AppDelegate.self)` on App struct
- Risks: Dock menu not visible in Xcode debugger — manual testing required outside IDE

### UI Layer

#### MenuBarPopoverView

| Field | Detail |
|-------|--------|
| Intent | SwiftUI view inside MenuBarExtra displaying sandbox list with status and quick actions |
| Requirements | 1.1–1.12 |

**Responsibilities & Constraints**
- Renders as a `.window`-style MenuBarExtra popover
- Reads `SandboxStore.sandboxes` for list content
- Groups by status (running first, then stopped)
- Provides Stop/Resume/Open in App actions per sandbox
- Includes "New Sandbox…" and "Quit" actions

**Dependencies**
- Inbound: SandboxStore — sandbox list and operations (P0)
- Outbound: NavigationCoordinator — "Open in App" navigation (P1)

**Contracts**: — (presentation only)

**Implementation Notes**
- Menu bar icon: Use SF Symbol `"shippingbox"` (matches sandbox metaphor). Running count displayed via label text: `MenuBarExtra("sbx (\(runningCount))", systemImage: "shippingbox.fill")` when running, `MenuBarExtra("sbx", systemImage: "shippingbox")` when idle.
- The popover shares stores via `.environment()` injection in the App body, identical to WindowGroup.

#### DropZoneOverlay

| Field | Detail |
|-------|--------|
| Intent | Visual overlay indicating a valid drop target on the dashboard |
| Requirements | 3.1, 3.5 |

Summary-only component. Renders a dashed border + "Drop to create sandbox" label when `isTargeted` is true. Follows design system colors (accent border, surface background with opacity).

#### DashboardView Modifications

| Field | Detail |
|-------|--------|
| Intent | Add `.onDrop` modifier and DropZoneOverlay to existing DashboardView |
| Requirements | 3.1–3.7 |

**Implementation Notes**
- Add `@State private var isDropTargeted = false` to DashboardView
- Add `.onDrop(of: [.fileURL], isTargeted: $isDropTargeted)` with handler that validates directory and either opens CreateProjectSheet or navigates to existing sandbox
- Overlay `DropZoneOverlay(isVisible: isDropTargeted)` on the ScrollView
- Validation: Check `url.hasDirectoryPath`; if false, return `false` from handler. If multiple items, use first.
- Dedup: Compare dropped path against `sandboxStore.sandboxes.map(\.workspace)` — if match found and sandbox is running, use NavigationCoordinator.

### App Intents Layer

#### SandboxEntity

| Field | Detail |
|-------|--------|
| Intent | AppEntity representing a sandbox for dynamic parameter resolution in Shortcuts |
| Requirements | 5.12 |

**Contracts**: State [x]

```swift
struct SandboxEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation
    static var defaultQuery: SandboxEntityQuery

    var id: String       // sandbox name
    var name: String
    var status: String

    var displayRepresentation: DisplayRepresentation
}

struct SandboxEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SandboxEntity]
    func suggestedEntities() async throws -> [SandboxEntity]
}
```

- `suggestedEntities()` returns all sandboxes from `ServiceContainer.shared.sandboxStore`
- `entities(for:)` filters by name match

#### Intent Structs (CreateSandboxIntent, StopSandboxIntent, ResumeSandboxIntent, TerminateSandboxIntent, ListSandboxesIntent)

| Field | Detail |
|-------|--------|
| Intent | Individual AppIntent conformances for each sandbox operation |
| Requirements | 5.1–5.11 |

**Contracts**: Service [x]

##### CreateSandboxIntent

```swift
struct CreateSandboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Sandbox"

    @Parameter(title: "Workspace Path")
    var workspacePath: String

    @Parameter(title: "Name", default: nil)
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String>
}
```

- Returns sandbox name as string result
- Calls `ServiceContainer.shared.sandboxStore.createSandbox(workspace:name:)`

##### StopSandboxIntent

```swift
struct StopSandboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Sandbox"

    @Parameter(title: "Sandbox")
    var sandbox: SandboxEntity

    @MainActor
    func perform() async throws -> some IntentResult
}
```

- If sandbox not found, throws intent error with descriptive message
- Other mutating intents (Resume, Terminate) follow the same pattern

##### ListSandboxesIntent

```swift
struct ListSandboxesIntent: AppIntent {
    static var title: LocalizedStringResource = "List Sandboxes"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]>
}
```

- Returns array of `"name (status)"` strings
- Calls `ServiceContainer.shared.sandboxStore.fetchSandboxes()` then maps

#### SbxShortcutsProvider

| Field | Detail |
|-------|--------|
| Intent | Registers Siri phrases for all intents |
| Requirements | 5.9 |

```swift
struct SbxShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateSandboxIntent(), phrases: ["Create a sandbox in \(.applicationName)"])
        AppShortcut(intent: StopSandboxIntent(), phrases: ["Stop sandbox in \(.applicationName)"])
        AppShortcut(intent: ListSandboxesIntent(), phrases: ["List my sandboxes in \(.applicationName)"])
    }
}
```

**Implementation Notes**
- Maximum 10 shortcuts allowed by the framework
- All mutating intents call `sandboxStore.fetchSandboxes()` after the operation to ensure UI reflects the change
- Intents use `@MainActor` on `perform()` for direct store access

## Data Models

### Domain Model

No new persistent data models. All five features consume existing domain types (`Sandbox`, `SandboxStatus`, `PolicyLogEntry`).

New transient types:
- `NavigationRequest` — enum representing a deep-link target (see NavigationCoordinator)
- `SandboxEntity` — AppEntity wrapper around `Sandbox` for the Intents framework (see App Intents Layer)
- Notification category identifiers — string constants (`sandbox-lifecycle`, `policy-violation`, `session-event`)

## Error Handling

### Error Strategy

| Error Source | Error Type | Response |
|-------------|-----------|----------|
| Notification authorization denied | User permission | Silently disable notifications; no error surfaced |
| Intent sandbox not found | Business logic | Return `IntentError` with localized message |
| Intent operation fails | CLI/service error | Map `SbxServiceError` to `IntentError` with user-facing description |
| Drop non-directory file | User input | Ignore drop silently (return `false`) |
| Dock menu action fails | CLI/service error | Log error via appLog; show toast if main window visible |
| Menu bar action fails | CLI/service error | Display inline error state in popover |

### Error Categories and Responses

**User Errors**: Invalid drop target (non-directory) → silently ignored. Invalid intent parameters → `IntentError` with guidance.
**System Errors**: CLI failures during intent/dock/menu bar actions → graceful degradation with logging. Notification delivery failure → no user-facing error (macOS handles delivery).
**Business Logic Errors**: Sandbox not found, already running → descriptive error messages in intent results and toast notifications.

## Testing Strategy

### Test Infrastructure & Protocols

New test doubles required to enable unit testing of macOS system APIs:

```swift
/// Abstracts UNUserNotificationCenter for testable notification posting.
/// Uses simple types instead of UNNotificationSettings (which has no public initializer).
protocol NotificationCenterProtocol: Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func isAuthorized() async -> Bool
}

/// Abstracts NSApplication window activation for testable navigation
protocol WindowActivatorProtocol {
    func activateMainWindow()
}

/// Records posted notifications for assertion in tests
actor MockNotificationCenter: NotificationCenterProtocol {
    var postedRequests: [UNNotificationRequest] = []
    var registeredCategories: Set<UNNotificationCategory> = []
    var authorizationGranted: Bool = true

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { authorizationGranted }
    func add(_ request: UNNotificationRequest) async throws { postedRequests.append(request) }
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { registeredCategories = categories }
    func isAuthorized() async -> Bool { authorizationGranted }
}

/// Records navigation requests for assertion in tests
@MainActor
final class MockWindowActivator: WindowActivatorProtocol {
    var activationCount = 0
    func activateMainWindow() { activationCount += 1 }
}
```

These follow the existing codebase pattern where `StubSbxService` and `FailingSbxService` are injected into stores for testing.

### Unit Tests (Swift Testing — `@Test`, `#expect`)

All unit tests use the existing patterns: `struct` test groups, `StubSbxService` injection, `await` for `@MainActor` store access.

#### ServiceContainer Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `sharedInstanceReturnsSameObject` | All | `ServiceContainer.shared` returns identical instance on repeated access |
| `storesAreInitialized` | All | All stores (`sandboxStore`, `policyStore`, `sessionStore`) are non-nil and functional after init |
| `navigationCoordinatorIsInitialized` | 1.9, 2.5, 3.7, 4.7 | `navigationCoordinator` is accessible and ready |
| `notificationManagerIsInitialized` | 2.1–2.10 | `notificationManager` is accessible and ready |

#### NavigationCoordinator Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `navigateSetsPendingNavigation` | 1.9 | `navigate(to: .sandbox(name: "test"))` sets `pendingNavigation` to `.sandbox(name: "test")` |
| `consumeReturnsAndClears` | 1.9 | `consumeNavigation()` returns the pending request, then returns `nil` on second call |
| `consumeReturnsNilWhenEmpty` | — | `consumeNavigation()` returns `nil` when no pending navigation |
| `navigateCallsActivateMainWindow` | 1.9, 2.5, 4.7 | `navigate(to:)` calls `WindowActivatorProtocol.activateMainWindow()` — verify via `MockWindowActivator.activationCount` |
| `multipleNavigatesOverwritesPending` | — | Second `navigate(to:)` replaces the first pending request (latest wins) |
| `allNavigationRequestCasesEquatable` | — | Verify `NavigationRequest` enum equality for `.sandbox`, `.policyLog`, `.createSheet`, `.createWithWorkspace` |

#### NotificationManager Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `requestAuthorizationSetsIsAuthorized` | 2.7 | After `requestAuthorization()`, `isAuthorized == true` when `MockNotificationCenter.authorizationGranted == true` |
| `requestAuthorizationDeniedSetsIsAuthorizedFalse` | 2.8 | `isAuthorized == false` when `authorizationGranted == false` |
| `creatingToRunningPostsCreationComplete` | 2.1 | `onSandboxesUpdated(previous: [creating], current: [running], busyOps: [:])` → `MockNotificationCenter.postedRequests` contains a request with category `sandbox-lifecycle` and "Creation Complete" in body |
| `runningToStoppedPostsUnexpectedStop` | 2.2 | `onSandboxesUpdated(previous: [running], current: [stopped], busyOps: [:])` → posted request contains "Unexpected Stop" |
| `runningToStoppedWithBusyStoppingSuppressesNotification` | 2.10 | `onSandboxesUpdated(previous: [running], current: [stopped], busyOps: ["test": .stopping])` → no notification posted |
| `policyViolationPostsNotification` | 2.3 | `postPolicyViolation(sandboxName: "test", blockedHost: "evil.com")` → posted request contains category `policy-violation` with blocked host in body |
| `sessionDisconnectedPostsNotification` | 2.4 | `postSessionDisconnected(sandboxName: "test")` → posted request contains category `session-event` |
| `noNotificationsWhenUnauthorized` | 2.8 | When `isAuthorized == false`, all post methods produce zero `postedRequests` |
| `categoriesRegisteredOnInit` | 2.9 | After initialization, `MockNotificationCenter.registeredCategories` contains `sandbox-lifecycle`, `policy-violation`, `session-event` |
| `threadIdentifierSetPerSandbox` | 2.9 | Posted notification for sandbox "foo" has `threadIdentifier == "sandbox-foo"` |
| `noChangeInStatePostsNoNotifications` | — | `onSandboxesUpdated(previous: [running], current: [running], busyOps: [:])` → no notifications posted |
| `multipleTransitionsPostMultipleNotifications` | 2.1, 2.2 | Two sandboxes changing state simultaneously → two separate notifications posted |

#### DockMenuBuilder Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `emptyStateShowsOnlyNewSandbox` | 4.9 | `buildDockMenu(sandboxes: [])` → menu has 1 item: "New Sandbox…" |
| `runningSandboxesAppearFirst` | 4.2 | `buildDockMenu(sandboxes: [stopped, running])` → running sandbox item is before stopped sandbox item |
| `runningSandboxHasStopAndOpenSubmenu` | 4.3 | Running sandbox menu item has submenu with "Stop" and "Open" items |
| `stoppedSandboxHasResumeAndOpenSubmenu` | 4.4 | Stopped sandbox menu item has submenu with "Resume" and "Open" items |
| `newSandboxItemAtTop` | 4.8 | First item in menu is always "New Sandbox…" regardless of sandbox count |
| `menuIncludesSeparatorAfterNewSandbox` | 4.1 | Second item is a separator when sandboxes exist |
| `allSandboxesRepresented` | 4.1 | 3 sandboxes → 3 sandbox items in menu (plus "New Sandbox…" and separator) |

#### App Intent Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `createSandboxIntentReturnsName` | 5.1, 5.6 | `CreateSandboxIntent.perform()` with workspace `/tmp/test` → returns sandbox name string |
| `createSandboxIntentWithCustomName` | 5.1 | `perform()` with name "custom" → returned name is "custom" |
| `stopSandboxIntentStopsSandbox` | 5.2 | `StopSandboxIntent.perform()` → sandbox status becomes `.stopped` |
| `stopSandboxIntentNotFoundThrows` | 5.7 | `perform()` with non-existent sandbox → throws descriptive intent error |
| `resumeSandboxIntentResumesSandbox` | 5.3 | `ResumeSandboxIntent.perform()` → sandbox status becomes `.running` |
| `resumeAlreadyRunningIsIdempotent` | 5.8 | `perform()` on running sandbox → succeeds without error |
| `terminateSandboxIntentRemovesSandbox` | 5.4 | `TerminateSandboxIntent.perform()` → sandbox removed from store |
| `listSandboxesIntentReturnsAll` | 5.5 | `ListSandboxesIntent.perform()` with 2 sandboxes → returns 2-element array with "name (status)" format |
| `listSandboxesIntentEmptyReturnsEmpty` | 5.5 | `perform()` with no sandboxes → returns empty array |
| `mutatingIntentTriggersRefresh` | 5.11 | After `StopSandboxIntent.perform()`, `sandboxStore.sandboxes` reflects updated state |

#### SandboxEntity Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `entityQueryReturnsMatchingEntities` | 5.12 | `entities(for: ["test"])` with sandbox named "test" → returns 1 entity |
| `entityQueryNonExistentReturnsEmpty` | 5.12 | `entities(for: ["ghost"])` → returns empty array |
| `suggestedEntitiesReturnsAll` | 5.12 | `suggestedEntities()` with 3 sandboxes → returns 3 entities |
| `entityDisplayRepresentation` | 5.10 | Entity for running sandbox has correct `displayRepresentation` with name and status |

#### SbxShortcutsProvider Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `appShortcutsNotEmpty` | 5.9 | `SbxShortcutsProvider.appShortcuts` is non-empty |
| `appShortcutsWithinLimit` | 5.9 | `appShortcuts.count <= 10` (framework limit) |

#### Drag & Drop Handler Logic Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `directoryDropReturnsTrue` | 3.6 | Handler with valid directory URL → returns `true` |
| `fileDropReturnsFalse` | 3.3 | Handler with file URL (not directory) → returns `false` |
| `multipleItemsUsesFirst` | 3.4 | Handler with 3 directory URLs → only first URL is used |
| `existingWorkspaceNavigatesInsteadOfCreate` | 3.7 | Dropped path matches running sandbox workspace → `NavigationCoordinator.pendingNavigation` set to `.sandbox(name:)`, create sheet NOT opened |

### UI/E2E Tests (XCTest — `XCTestCase`, `XCUIApplication`)

UI tests follow the existing patterns: `XCUIApplication` with CLI mock via `SBX_CLI_MOCK=1`, `waitForExistence(timeout:)`, accessibility identifiers.

#### New Accessibility Identifiers Required

| Identifier | Component | Purpose |
|-----------|-----------|---------|
| `menuBarSandboxItem-{name}` | MenuBarPopoverView | Sandbox row in menu bar popover |
| `menuBarStopButton-{name}` | MenuBarPopoverView | Stop action in popover |
| `menuBarResumeButton-{name}` | MenuBarPopoverView | Resume action in popover |
| `menuBarOpenButton-{name}` | MenuBarPopoverView | "Open in App" action |
| `menuBarNewSandboxButton` | MenuBarPopoverView | "New Sandbox…" action |
| `menuBarQuitButton` | MenuBarPopoverView | "Quit" action |
| `dropZoneOverlay` | DropZoneOverlay | Drop target visual indicator |

#### Menu Bar Extra E2E Tests

| Test | Requirement | Description |
|------|------------|-------------|
| `testMenuBarIconExistsOnLaunch` | 1.1 | `app.menuBarItems` contains the sbx-ui menu bar extra |
| `testMenuBarPopoverShowsSandboxList` | 1.4 | After creating a sandbox, click menu bar → popover shows sandbox name and status |
| `testMenuBarStopActionStopsSandbox` | 1.7 | Click Stop in popover → sandbox status changes to STOPPED on dashboard |
| `testMenuBarResumeActionResumesSandbox` | 1.8 | Click Resume in popover → sandbox status changes to LIVE |
| `testMenuBarOpenInAppNavigates` | 1.9 | Click "Open in App" → main window comes to front, session panel opens |
| `testMenuBarNewSandboxOpensSheet` | 1.10 | Click "New Sandbox…" → create sheet appears in main window |
| `testMenuBarQuitTerminatesApp` | 1.11 | Click Quit → app terminates |
| `testMenuBarCountBadge` | 1.2, 1.3 | With 2 running sandboxes, menu bar label shows count; with 0, no count shown |

#### Drag & Drop E2E Tests

Note: XCUITest has limited drag & drop simulation. The core handler logic is tested via unit tests. UI tests cover the visual overlay behavior where possible.

| Test | Requirement | Description |
|------|------------|-------------|
| `testDropZoneOverlayExistsInHierarchy` | 3.1 | `DropZoneOverlay` view is part of the DashboardView hierarchy (verify via accessibility identifier) |

#### Notification E2E Tests

Note: macOS notification banners cannot be directly asserted in XCUITest. Notification posting is verified via unit tests on `NotificationManager`. E2E tests verify the navigation behavior when `NavigationCoordinator` receives a request (simulating what happens after notification click).

| Test | Requirement | Description |
|------|------------|-------------|
| `testNavigationCoordinatorNavigatesToSandbox` | 2.5 | Set `pendingNavigation = .sandbox(name:)` → verify session panel opens for that sandbox |
| `testNavigationCoordinatorNavigatesToPolicyLog` | 2.6 | Set `pendingNavigation = .policyLog(sandboxName:)` → verify policy view opens |

#### Dock Menu Tests

Dock menu is not accessible via XCUITest when running from Xcode. Menu construction logic is tested via unit tests on `DockMenuBuilder`. Manual testing checklist:

- [ ] Right-click dock icon → menu shows "New Sandbox…"
- [ ] With running sandbox → submenu shows "Stop" and "Open"
- [ ] With stopped sandbox → submenu shows "Resume" and "Open"
- [ ] "Stop" action → sandbox stops
- [ ] "Open" action → main window activates with sandbox selected

#### App Intents E2E Tests

App Intents are best tested via unit tests on `perform()`. System-level validation via Shortcuts app:

- [ ] Open Shortcuts app → search "sbx" → all 5 intents appear with correct titles
- [ ] Create Sandbox shortcut → prompts for workspace path → creates sandbox
- [ ] Stop Sandbox shortcut → shows dynamic sandbox picker → stops selected sandbox
- [ ] List Sandboxes shortcut → returns sandbox names with status
- [ ] Siri: "List my sandboxes in sbx-ui" → returns result

### Integration Tests (Swift Testing)

Integration tests verify cross-component flows within a single test process.

| Test | Requirements | Description |
|------|-------------|-------------|
| `testNotificationFlowOnSandboxCreation` | 2.1, 2.5 | Create sandbox via `SandboxStore` → verify `MockNotificationCenter` received creation notification → simulate notification click → verify `NavigationCoordinator.pendingNavigation` set to `.sandbox(name:)` |
| `testNotificationFlowSuppressesUserStop` | 2.2, 2.10 | Stop sandbox via `SandboxStore.stopSandbox()` (sets `busyOperations[.stopping]`) → trigger `onSandboxesUpdated` → verify NO "unexpected stop" notification posted |
| `testIntentStoreRoundTrip` | 5.2, 5.11 | Create sandbox → invoke `StopSandboxIntent.perform()` → verify `sandboxStore.sandboxes.first?.status == .stopped` |
| `testDockMenuAfterStateChange` | 4.5, 4.10 | Create sandbox → build dock menu → verify running item → stop sandbox → rebuild menu → verify stopped item |
| `testNavigationCoordinatorWithMenuBar` | 1.9 | Trigger `navigate(to: .sandbox(name:))` from menu bar context → verify `pendingNavigation` set and `MockWindowActivator.activationCount == 1` |
| `testDropHandlerWithExistingWorkspace` | 3.7 | Create sandbox with workspace "/tmp/test" → invoke drop handler with same path → verify `NavigationCoordinator.pendingNavigation == .sandbox(name:)` |

### Test Summary

| Category | Framework | Count | Automatable |
|----------|-----------|-------|-------------|
| Unit — ServiceContainer | Swift Testing | 4 | Yes |
| Unit — NavigationCoordinator | Swift Testing | 6 | Yes |
| Unit — NotificationManager | Swift Testing | 12 | Yes |
| Unit — DockMenuBuilder | Swift Testing | 7 | Yes |
| Unit — App Intents | Swift Testing | 10 | Yes |
| Unit — SandboxEntity | Swift Testing | 4 | Yes |
| Unit — SbxShortcutsProvider | Swift Testing | 2 | Yes |
| Unit — Drop Handler | Swift Testing | 4 | Yes |
| UI/E2E — Menu Bar Extra | XCTest | 8 | Yes |
| UI/E2E — Drag & Drop | XCTest | 1 | Partial |
| UI/E2E — Navigation | XCTest | 2 | Yes |
| Integration | Swift Testing | 6 | Yes |
| Manual — Dock Menu | — | 5 | No |
| Manual — App Intents | — | 5 | No |
| **Total** | | **76** | **59 auto / 10 manual** |
