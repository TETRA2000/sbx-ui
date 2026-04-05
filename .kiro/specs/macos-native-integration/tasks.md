# Implementation Plan

- [x] 1. Foundation — ServiceContainer and NavigationCoordinator
- [x] 1.1 Create the shared service container with configurable singleton
  - Introduce a centralized container that holds the single service instance and all stores (sandbox, policy, session), plus the new navigation coordinator and notification manager
  - Expose a `configure` class method so tests can replace the backing service with a stub
  - The default initializer creates stores using the production service factory
  - _Requirements: 1.12, 2.7, 4.10, 5.11_

- [x] 1.2 (P) Create the navigation coordinator with window activation abstraction
  - Define a navigation request type covering four cases: open sandbox session, open policy log filtered to a sandbox, open the create sheet, and open the create sheet pre-filled with a workspace path
  - Implement a coordinator that accepts navigation requests, stores the latest pending request, and activates the main window via a window activator protocol
  - Provide a consume method that returns and clears the pending request
  - Inject a window activator protocol so that tests can substitute a mock (records activation call count)
  - _Requirements: 1.9, 1.10, 2.5, 2.6, 3.7, 4.7, 4.8_

- [x] 1.3 Refactor the app entry point to use the service container
  - Replace the per-store initialization in the App struct with reads from the shared container
  - Keep environment injection unchanged — views still receive stores through SwiftUI environment
  - Ensure the existing app behavior (window group, polling, debug log) is unaffected
  - _Requirements: 1.12_

- [x] 1.4 Unit tests for service container and navigation coordinator
  - Verify the shared instance returns the same object on repeated access
  - Verify `configure` replaces the shared instance with one backed by a stub service
  - Verify navigate sets the pending request and calls the window activator
  - Verify consume returns and clears the pending request, and returns nil when empty
  - Verify multiple navigates overwrite the pending request (latest wins)
  - Run the full test suite to confirm no regressions from the refactor
  - _Requirements: 1.9, 1.12_

- [x] 2. System Notifications
- [x] 2.1 (P) Create the notification center protocol and notification manager
  - Define a notification center protocol with methods for authorization request, posting notification requests, registering categories, and checking authorization status (simple boolean, not UNNotificationSettings)
  - Implement the production wrapper that delegates to UNUserNotificationCenter
  - Implement the notification manager that requests authorization on initialization, tracks authorization status, and registers three notification categories: sandbox lifecycle, policy violation, and session event
  - Each category defines a foreground action ("Open", "View Log", or "Reconnect") and uses per-sandbox thread identifiers for grouping
  - _Requirements: 2.7, 2.8, 2.9_

- [x] 2.2 (P) Implement notification state diffing and posting logic
  - Add the sandbox-updated callback that receives previous and current sandbox lists plus the busy operations map
  - Detect creating-to-running transitions and post a "Creation Complete" notification
  - Detect running-to-stopped transitions; check whether the sandbox name appears in busy operations as stopping — if so, suppress the notification; otherwise post "Unexpected Stop"
  - Add methods to post policy violation notifications (sandbox name + blocked host) and session disconnect notifications (sandbox name)
  - Only post when the manager reports authorized
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.10_

- [x] 2.3 Unit tests for notification manager
  - Create a mock notification center that records posted requests, registered categories, and configurable authorization result
  - Test authorization granted and denied paths
  - Test creating-to-running posts "Creation Complete" with correct category and thread identifier
  - Test running-to-stopped posts "Unexpected Stop" when no busy operation present
  - Test running-to-stopped suppresses notification when busy operations contain stopping
  - Test policy violation and session disconnect posting
  - Test no notifications posted when unauthorized
  - Test categories are registered on initialization
  - Test no notifications posted when sandbox state is unchanged
  - Test multiple simultaneous transitions post multiple notifications
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.7, 2.8, 2.9, 2.10_

- [ ] 3. Menu Bar Extra
- [ ] 3.1 (P) Add the menu bar extra scene with popover view
  - Add a MenuBarExtra scene as a sibling to the existing WindowGroup in the App body, using the window popover style
  - Display a shipping-box system image as the icon; append the running sandbox count to the label when at least one sandbox is running; show no count when idle
  - Inject the shared stores into the menu bar scene via environment, identical to the window group
  - _Requirements: 1.1, 1.2, 1.3, 1.12_

- [ ] 3.2 (P) Build the menu bar popover content with sandbox list and actions
  - List all sandboxes grouped by status (running first, then stopped), showing name and status for each
  - For running sandboxes, provide "Stop" and "Open in App" action buttons
  - For stopped sandboxes, provide "Resume" and "Open in App" action buttons
  - Stop and Resume call the corresponding sandbox store methods
  - "Open in App" triggers the navigation coordinator with the sandbox name
  - Include a "New Sandbox…" button that triggers the navigation coordinator with the create-sheet request
  - Include a "Quit" button that terminates the application
  - Add accessibility identifiers for all interactive elements
  - _Requirements: 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11_

- [ ] 3.3 UI tests for menu bar extra
  - Verify the menu bar icon exists on app launch
  - Verify the popover shows the sandbox list after creating a sandbox
  - Verify Stop action changes sandbox status to stopped on the dashboard
  - Verify Resume action changes sandbox status back to running
  - Verify "Open in App" navigates to the sandbox session view
  - Verify "New Sandbox…" opens the create sheet in the main window
  - Verify the running count badge appears with running sandboxes and disappears when idle
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.7, 1.8, 1.9, 1.10_

- [ ] 4. Drag & Drop Workspace
- [x] 4.1 (P) Add the drop zone overlay and onDrop handler to the dashboard
  - Create a drop zone overlay view that renders a dashed border and "Drop to create sandbox" label when the targeted state is active, using design system colors
  - Add the drop zone overlay on top of the dashboard scroll view, bound to a targeted state boolean
  - Attach an onDrop handler accepting file URLs on the dashboard view
  - In the handler: load the URL, validate it is a directory (ignore non-directories and use only the first item if multiple), check whether the path matches an existing running sandbox workspace (navigate to it if so), and otherwise open the create sheet pre-filled with the dropped path
  - Add accessibility identifier for the drop zone overlay
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

- [x] 4.2 (P) Unit tests for drag and drop handler logic
  - Extract the drop validation and routing logic into a testable function
  - Test that a valid directory returns true and sets the appropriate create-with-workspace navigation request
  - Test that a non-directory file returns false with no side effects
  - Test that multiple items use only the first directory
  - Test that a directory matching an existing running sandbox's workspace navigates to that sandbox instead of opening the create sheet
  - _Requirements: 3.3, 3.4, 3.6, 3.7_

- [ ] 5. Dock Menu
- [x] 5.1 (P) Create the dock menu builder as a pure function
  - Implement a standalone function that takes a list of sandboxes and returns a constructed menu
  - Always include "New Sandbox…" as the first item
  - Add a separator when sandboxes exist
  - Group sandboxes by status: running first, then stopped
  - Running sandbox items get a submenu with "Stop" and "Open"
  - Stopped sandbox items get a submenu with "Resume" and "Open"
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.8, 4.9_

- [x] 5.2 (P) Unit tests for dock menu builder
  - Test empty state produces only "New Sandbox…"
  - Test running sandboxes appear before stopped sandboxes
  - Test running sandbox submenu contains "Stop" and "Open"
  - Test stopped sandbox submenu contains "Resume" and "Open"
  - Test "New Sandbox…" is always the first item
  - Test separator present after "New Sandbox…" when sandboxes exist
  - Test all sandboxes are represented in the menu
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.8, 4.9_

- [x] 6. App Intents and Shortcuts
- [x] 6.1 (P) Create the sandbox entity and entity query
  - Define an app entity representing a sandbox with name, status, and display representation
  - Implement an entity query that fetches entities by identifier from the shared container's sandbox store
  - Implement suggested entities that returns all sandboxes
  - _Requirements: 5.10, 5.12_

- [x] 6.2 (P) Implement the five sandbox intent structs
  - Create Sandbox intent: accepts workspace path (required) and optional name, creates the sandbox via the store, returns the sandbox name as the result
  - Stop Sandbox intent: accepts a sandbox entity parameter, stops the sandbox, returns descriptive error if the sandbox does not exist
  - Resume Sandbox intent: accepts a sandbox entity parameter, resumes the sandbox, returns success without error if already running (idempotent)
  - Terminate Sandbox intent: accepts a sandbox entity parameter, removes the sandbox
  - List Sandboxes intent: takes no parameters, refreshes the sandbox list, returns an array of name-status strings
  - All mutating intents trigger a sandbox list refresh after the operation
  - All intents include parameter summaries and descriptions for clear Shortcuts labels
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.10, 5.11_

- [x] 6.3 (P) Create the shortcuts provider with Siri phrases
  - Register predefined Siri phrases for creating a sandbox, stopping a sandbox, and listing sandboxes
  - Ensure the total number of registered shortcuts stays within the framework limit of 10
  - _Requirements: 5.9_

- [x] 6.4 Unit tests for app intents and sandbox entity
  - Configure the service container with a stub service in test setup
  - Test create intent returns the correct sandbox name
  - Test create intent with custom name uses that name
  - Test stop intent stops the sandbox
  - Test stop intent with non-existent sandbox throws a descriptive error
  - Test resume intent resumes the sandbox
  - Test resume on an already-running sandbox succeeds without error
  - Test terminate intent removes the sandbox from the store
  - Test list intent returns all sandboxes with correct name-status format
  - Test list intent with no sandboxes returns empty
  - Test mutating intents trigger store refresh
  - Test entity query returns matching entities and empty for non-existent
  - Test suggested entities returns all sandboxes
  - Test shortcuts provider is non-empty and within the 10-shortcut limit
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 5.9, 5.10, 5.11, 5.12_

- [x] 7. AppDelegate — Dock Menu and Notification Delegate Wiring
  - Requires tasks 1, 2, and 5 to be complete
- [x] 7.1 Create the app delegate with dock menu and notification delegate
  - Add an NSApplicationDelegateAdaptor to the App struct
  - Implement the dock menu callback using the dock menu builder from task 5, passing the current sandbox list from the shared container
  - Wire menu item actions to dispatch stop, resume, and open operations to the stores and navigation coordinator on the main actor
  - Set the delegate as the notification center delegate in the did-finish-launching callback
  - Handle notification click responses by parsing the category identifier and sandbox name from the notification content, then forwarding the appropriate navigation request to the coordinator
  - _Requirements: 2.5, 2.6, 4.1, 4.3, 4.4, 4.5, 4.6, 4.7, 4.10_

- [x] 8. Integration Wiring and Final Testing
  - Requires all previous tasks to be complete
- [x] 8.1 Wire NavigationCoordinator observation into ShellView
  - Add an onChange observer on the navigation coordinator's pending navigation property
  - When a sandbox request arrives, find or start the agent session and set the selected session ID
  - When a policy-log request arrives, switch sidebar selection to policies (filtered sandbox context can be set if the policy view supports it)
  - When a create-sheet or create-with-workspace request arrives, set the show-create-sheet flag (and pre-fill workspace if provided)
  - Consume the pending navigation after handling
  - _Requirements: 1.9, 2.5, 2.6, 3.7, 4.7_

- [x] 8.2 Wire notification state diffing via SwiftUI onChange
  - Add an onChange observer on the sandbox store's sandbox list in ShellView or the App body
  - Capture the previous sandbox list and pass both previous and current lists along with the busy operations map to the notification manager's on-sandboxes-updated method
  - This keeps the sandbox store decoupled from the notification system
  - _Requirements: 2.1, 2.2, 2.10_

- [x] 8.3 Integration tests
  - Test the full notification flow: create a sandbox via the store, verify the mock notification center received a creation notification, simulate a notification click response, verify the navigation coordinator received the correct sandbox navigation request
  - Test notification suppression: stop a sandbox via the store (which sets the busy-stopping operation), trigger the sandboxes-updated callback, verify no unexpected-stop notification was posted
  - Test intent-to-store round-trip: create a sandbox, invoke the stop intent perform method, verify the store's sandbox list reflects the stopped status
  - Test dock menu after state change: create a sandbox, build the dock menu and verify a running item, stop the sandbox, rebuild and verify a stopped item
  - Test navigation coordinator with menu bar context: trigger a navigate-to-sandbox request, verify pending navigation is set and window activator was called
  - Test drop handler with existing workspace: create a sandbox with a specific workspace, invoke the drop handler with the same path, verify navigation coordinator received a sandbox navigation request
  - _Requirements: 1.9, 2.1, 2.2, 2.5, 2.10, 3.7, 4.5, 4.10, 5.2, 5.11_

- [x] 8.4 E2E tests for menu bar and navigation
  - Verify the menu bar icon exists on launch and shows sandbox list after creation
  - Verify menu bar stop and resume actions update dashboard status
  - Verify "Open in App" from menu bar navigates to the correct session
  - Verify drop zone overlay exists in the dashboard view hierarchy
  - Verify navigation coordinator sandbox request opens the session panel
  - Verify navigation coordinator policy-log request opens the policy view
  - Run the full test suite (all existing + new tests) and confirm zero regressions
  - _Requirements: 1.1, 1.4, 1.7, 1.8, 1.9, 2.5, 2.6, 3.1_
