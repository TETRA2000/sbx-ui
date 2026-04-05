# Requirements Document

## Introduction
macOS Native Integration extends sbx-ui with five platform-specific features that make it behave as a first-class macOS developer tool. Menu Bar Extra provides persistent system-level sandbox monitoring. UserNotifications delivers proactive alerts for sandbox lifecycle events. Drag & Drop enables frictionless sandbox creation from Finder. Dock Menu offers quick sandbox actions without opening the main window. App Intents exposes sandbox operations to Shortcuts and Siri for automation. Together, these features allow developers to monitor, control, and automate sandboxes from anywhere in macOS — not just the app window.

## Requirements

### Requirement 1: Menu Bar Extra
**Objective:** As a developer, I want a persistent menu bar icon showing sandbox status with a dropdown for quick actions, so that I can monitor and control sandboxes without switching to the main app window.

#### Acceptance Criteria
1. The App shall display a menu bar icon using `MenuBarExtra` that is visible whenever the application is running.
2. The App shall display the count of currently running sandboxes as a badge or label next to the menu bar icon.
3. When no sandboxes are running, the App shall display the menu bar icon in an inactive/dimmed style with no count badge.
4. When the user clicks the menu bar icon, the App shall display a popover listing all sandboxes with their name and current status (running, stopped, creating, removing).
5. When the user clicks a running sandbox in the menu bar popover, the App shall present "Stop" and "Open in App" actions for that sandbox.
6. When the user clicks a stopped sandbox in the menu bar popover, the App shall present "Resume" and "Open in App" actions for that sandbox.
7. When the user selects "Stop" from the menu bar popover, the App shall stop the sandbox and update the popover list to reflect the new status.
8. When the user selects "Resume" from the menu bar popover, the App shall resume the sandbox and update the popover list to reflect the new status.
9. When the user selects "Open in App" from the menu bar popover, the App shall bring the main window to the foreground and navigate to that sandbox's session view.
10. The App shall include a "New Sandbox…" action in the menu bar popover that opens the main window with the create sandbox sheet.
11. The App shall include a "Quit" action in the menu bar popover that terminates the application.
12. While the sandbox list is polling, the menu bar popover shall reflect the same data as the dashboard without requiring a separate polling mechanism.

### Requirement 2: System Notifications
**Objective:** As a developer, I want macOS notifications for important sandbox lifecycle events, so that I am alerted to state changes even when focused on other work.

#### Acceptance Criteria
1. When a sandbox transitions from "creating" to "running", the App shall post a macOS notification with the sandbox name and a "Creation Complete" message.
2. When a sandbox transitions from "running" to "stopped" without user-initiated stop action, the App shall post a macOS notification with the sandbox name and an "Unexpected Stop" message.
3. When a network policy violation is detected in the policy activity log (blocked request), the App shall post a macOS notification with the sandbox name, blocked host, and a "Policy Violation" message.
4. When a terminal session disconnects unexpectedly (process exit while the session view is not actively being closed by the user), the App shall post a macOS notification with the sandbox name and a "Session Disconnected" message.
5. When the user clicks a sandbox lifecycle notification (creation complete, unexpected stop), the App shall bring the main window to the foreground and navigate to the relevant sandbox's view.
6. When the user clicks a policy violation notification, the App shall bring the main window to the foreground and navigate to the policy log view filtered to the relevant sandbox.
7. The App shall request notification authorization from the user via `UNUserNotificationCenter` on first launch.
8. If the user has denied notification permissions, the App shall not attempt to post notifications and shall not display errors related to notification delivery.
9. The App shall define distinct notification categories for lifecycle events, policy violations, and session events so that users can configure per-category delivery in System Settings.
10. While a user-initiated stop is in progress (the user clicked the stop button), the App shall suppress the "Unexpected Stop" notification for that sandbox.

### Requirement 3: Drag & Drop Workspace
**Objective:** As a developer, I want to drag a project folder from Finder onto the sbx-ui window to create a sandbox, so that I can start sandbox creation with minimal clicks.

#### Acceptance Criteria
1. When the user drags a directory from Finder over the dashboard area, the App shall display a visual drop zone overlay indicating that dropping will create a sandbox.
2. When the user drops a directory onto the dashboard drop zone, the App shall open the Create Sandbox sheet with the workspace path pre-filled from the dropped directory.
3. When the user drops a non-directory file onto the dashboard, the App shall ignore the drop and not display the create sheet.
4. When the user drops multiple directories onto the dashboard, the App shall use only the first directory and ignore the rest.
5. While a drop zone overlay is displayed and the user drags the item out of the dashboard area, the App shall dismiss the drop zone overlay.
6. The App shall accept drops using `onDrop` with `UTType.fileURL` conformance and validate that the dropped URL is a directory.
7. When the user drops a directory whose path matches an existing running sandbox's workspace, the App shall navigate to that sandbox instead of opening the create sheet.

### Requirement 4: Dock Menu
**Objective:** As a developer, I want to right-click the sbx-ui dock icon to see running sandboxes and take quick actions, so that I can control sandboxes without opening the main window.

#### Acceptance Criteria
1. When the user right-clicks (or long-presses) the dock icon, the App shall display a dynamic dock menu listing all sandboxes with their current status.
2. The dock menu shall group sandboxes by status: running sandboxes first, then stopped sandboxes.
3. When the user clicks a running sandbox in the dock menu, the App shall present a submenu with "Stop" and "Open" actions.
4. When the user clicks a stopped sandbox in the dock menu, the App shall present a submenu with "Resume" and "Open" actions.
5. When the user selects "Stop" from the dock menu, the App shall stop the sandbox and the next dock menu invocation shall reflect the updated status.
6. When the user selects "Resume" from the dock menu, the App shall resume the sandbox and the next dock menu invocation shall reflect the updated status.
7. When the user selects "Open" from the dock menu, the App shall bring the main window to the foreground and navigate to that sandbox's session view.
8. The App shall include a "New Sandbox…" item at the top of the dock menu that opens the main window with the create sandbox sheet.
9. When no sandboxes exist, the dock menu shall display only the "New Sandbox…" item.
10. The dock menu shall rebuild its contents each time it is invoked to ensure it reflects the current sandbox state.

### Requirement 5: App Intents & Shortcuts
**Objective:** As a developer, I want sandbox operations exposed as App Intents, so that I can automate sandbox workflows via Shortcuts, Siri, and Spotlight.

#### Acceptance Criteria
1. The App shall expose a "Create Sandbox" intent that accepts a workspace path (string) and optional name (string) parameters, creates a sandbox, and returns the sandbox name.
2. The App shall expose a "Stop Sandbox" intent that accepts a sandbox name parameter and stops the specified sandbox.
3. The App shall expose a "Resume Sandbox" intent that accepts a sandbox name parameter and resumes the specified sandbox.
4. The App shall expose a "Terminate Sandbox" intent that accepts a sandbox name parameter and removes the specified sandbox.
5. The App shall expose a "List Sandboxes" intent that takes no parameters and returns a list of sandbox names with their current status.
6. When a Shortcuts user invokes the "Create Sandbox" intent with a valid workspace path, the App shall create the sandbox and return the resulting sandbox name as the intent result.
7. If a Shortcuts user invokes the "Stop Sandbox" intent with a sandbox name that does not exist, the App shall return an intent error with a descriptive message.
8. If a Shortcuts user invokes the "Resume Sandbox" intent with a sandbox that is already running, the App shall return success without error (idempotent).
9. The App shall provide an `AppShortcutsProvider` with predefined phrases for Siri, including: "Create a sandbox", "Stop sandbox [name]", "List my sandboxes".
10. The App shall register all intents with parameter summaries and descriptions so they appear with clear labels in the Shortcuts app.
11. When any intent modifies sandbox state (create, stop, resume, terminate), the App shall trigger a sandbox list refresh so the dashboard reflects the change.
12. The App shall expose sandbox name parameters as dynamic lookup entities via `DynamicOptionsProvider` so Shortcuts users can pick from existing sandboxes.
