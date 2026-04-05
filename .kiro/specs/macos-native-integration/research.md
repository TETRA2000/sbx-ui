# Research & Design Decisions

## Summary
- **Feature**: macos-native-integration
- **Discovery Scope**: Extension (adding 5 new macOS platform features to an existing SwiftUI app)
- **Key Findings**:
  - MenuBarExtra coexists with WindowGroup as sibling Scenes; shares @Observable stores via .environment() — no architectural refactor needed
  - Dock menu and notification delegate both require @NSApplicationDelegateAdaptor, which becomes the single AppKit bridge point
  - App Intents need access to stores outside the SwiftUI view hierarchy — requires a shared ServiceContainer singleton

## Research Log

### MenuBarExtra API (SwiftUI, macOS 13+)
- **Context**: Need persistent menu bar presence with dynamic sandbox count and quick actions
- **Sources**: Apple Developer Documentation (MenuBarExtra, MenuBarExtraStyle)
- **Findings**:
  - Declared as sibling Scene alongside WindowGroup in App body
  - Two styles: `.menu` (pull-down NSMenu) and `.window` (floating SwiftUI popover)
  - `.window` style supports full SwiftUI views — best for our popover with sandbox list + actions
  - No native badge API; use SF Symbol number variants (e.g., `"1.circle"`) or custom NSImage for count display
  - Shares @State/@Observable stores with WindowGroup when both reference the same instance on the App struct
- **Implications**: Minimal code — add a new Scene and a SwiftUI view. No architecture change needed.

### UNUserNotificationCenter (macOS)
- **Context**: Post notifications for sandbox lifecycle events, policy violations, session disconnects
- **Sources**: Apple Developer Documentation (UserNotifications), macOS behavior notes
- **Findings**:
  - Authorization: `requestAuthorization(options: [.alert, .sound, .badge])` — call in App init or didFinishLaunching
  - macOS defaults to banner style; user must change to "Alerts" in System Settings for persistent notifications
  - `.provisional` authorization not available on macOS
  - `UNUserNotificationCenterDelegate.didReceive` not called if app was terminated before click
  - Categories: `UNNotificationCategory` groups actions; `threadIdentifier` groups in Notification Center
  - Must set delegate before app finishes launching
- **Implications**: Requires @NSApplicationDelegateAdaptor to set delegate early. Need to track user-initiated stops to suppress false "unexpected stop" notifications.

### Drag & Drop in SwiftUI (macOS)
- **Context**: Drop folders from Finder onto dashboard to create sandboxes
- **Sources**: Apple Developer Documentation (onDrop, DropDelegate), UniformTypeIdentifiers
- **Findings**:
  - `.onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in ... }`
  - `isTargeted` binding toggles when valid drag hovers — use for overlay styling
  - Validate directory: `url.hasDirectoryPath` or `FileManager.fileExists(atPath:isDirectory:)`
  - `DropDelegate` protocol for granular control (validateDrop, dropEntered, dropExited)
  - Load URL via `provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)`
- **Implications**: Simple modifier on DashboardView. No architecture change. Need overlay view for visual feedback.

### NSApplication.dockMenu (AppKit)
- **Context**: Dynamic right-click menu on dock icon showing sandboxes with actions
- **Sources**: Apple Developer Documentation (applicationDockMenu)
- **Findings**:
  - Requires `@NSApplicationDelegateAdaptor` with `applicationDockMenu(_:) -> NSMenu?`
  - Called each time user right-clicks — rebuild menu from current state
  - NSMenu/NSMenuItem with target-action pattern
  - Wire to @Observable stores via reference on AppDelegate
  - Dock menu does NOT appear when debugging from Xcode
- **Implications**: Shares the same @NSApplicationDelegateAdaptor as notification delegate. AppDelegate needs store references.

### App Intents Framework (macOS 13+)
- **Context**: Expose sandbox CRUD as Shortcuts/Siri actions
- **Sources**: Apple Developer Documentation (AppIntent, AppEntity, AppShortcutsProvider, DynamicOptionsProvider)
- **Findings**:
  - `AppIntent` struct with `static var title` and `func perform() async throws -> some IntentResult`
  - `@Parameter` for input, supports `title`, `description`, `requestValueDialog`
  - `AppEntity` for exposing sandboxes as entities (requires `EntityQuery`)
  - `AppShortcutsProvider` for Siri phrases — limit of 10 shortcuts
  - `DynamicOptionsProvider` for dynamic sandbox name picker
  - `perform()` can be `@MainActor` for direct store access
  - `@Dependency` resolves shared services at runtime
- **Implications**: Intents run outside the SwiftUI view hierarchy. Need a `ServiceContainer` singleton so both App and Intents share the same SandboxStore instance. All mutating intents must refresh the store and trigger UI update.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Direct store access from AppDelegate | AppDelegate holds references to stores | Simple, no new abstractions | Tight coupling, hard to test | Rejected |
| ServiceContainer singleton | Shared container with service + stores, accessed by App, AppDelegate, and Intents | Single source of truth, testable | Singleton pattern adds global state | Selected |
| Notification-based coordination | NSNotificationCenter for cross-component events | Loose coupling | Hard to debug, type-unsafe | Rejected |

## Design Decisions

### Decision: ServiceContainer Singleton
- **Context**: App Intents, dock menu, and notification handlers all need access to SandboxStore outside the SwiftUI view hierarchy
- **Alternatives**:
  1. Pass store references through AppDelegate — couples everything to AppDelegate
  2. Create separate service instances per entry point — state divergence
  3. Shared ServiceContainer singleton — single canonical state
- **Selected**: ServiceContainer singleton holding `SbxServiceProtocol`, `SandboxStore`, `PolicyStore`
- **Rationale**: App Intents framework resolves dependencies at runtime, not through SwiftUI environment. A singleton container is the standard pattern for this.
- **Trade-offs**: Introduces global mutable state, but it's inherently shared state (sandbox list). Testable via protocol injection.

### Decision: NavigationCoordinator for Deep Linking
- **Context**: Menu bar, dock menu, notifications, and intents all need to navigate the main window to a specific sandbox or view
- **Alternatives**:
  1. Direct manipulation of ShellView bindings — requires passing bindings everywhere
  2. NotificationCenter posts — type-unsafe, fragile
  3. Dedicated NavigationCoordinator @Observable — centralized, type-safe
- **Selected**: NavigationCoordinator with a `pendingNavigation` property observed by ShellView
- **Rationale**: Single point of coordination; ShellView already manages navigation state. Coordinator just provides an external trigger.
- **Trade-offs**: One more @Observable to inject, but eliminates ad-hoc navigation logic in multiple places.

### Decision: Notification State Diffing in SandboxStore
- **Context**: Need to detect "unexpected stop" vs "user-initiated stop" for notification suppression
- **Selected**: SandboxStore already tracks `busyOperations` with `.stopping` state. NotificationManager checks this before posting "unexpected stop."
- **Rationale**: No new tracking needed — the existing `busyOperations` dictionary is the source of truth for user-initiated operations.

## Risks & Mitigations
- **Risk**: App Intents not discoverable in Shortcuts if metadata is wrong → Mitigation: Comprehensive parameter summaries and `AppShortcutsProvider` with explicit phrases
- **Risk**: Notification permission denied silently breaks notification feature → Mitigation: Check authorization status before posting; no error surfaced to user
- **Risk**: Dock menu not testable in Xcode debugger → Mitigation: Unit test menu construction logic separately; manual testing outside debugger
- **Risk**: MenuBarExtra .window style has limited customization → Mitigation: Fall back to .menu style if popover UX is insufficient

## References
- [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra)
- [UNUserNotificationCenter — Apple Developer Documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [onDrop — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:))
- [applicationDockMenu — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/1428564-applicationdockmenu)
- [App Intents — Apple Developer Documentation](https://developer.apple.com/documentation/appintents)
- [AppShortcutsProvider — Apple Developer Documentation](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
