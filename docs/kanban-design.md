# Kanban Task Management — Design Document

## Overview

The Kanban feature adds a task orchestration board to sbx-ui, enabling users to organize, sequence, and monitor multiple AI agent tasks through a visual kanban interface. Inspired by [Cline Kanban](https://cline.bot/kanban), it adapts the multi-agent orchestration concept to the native macOS SwiftUI environment.

## Problem

sbx-ui manages sandboxes individually. Users running multiple AI agents lack a unified view to plan task ordering, set dependencies between tasks, and monitor parallel work — the cognitive overhead grows linearly with agent count.

## Solution

A kanban board integrated into the sidebar navigation where users can:

- Create task cards with agent instructions (prompts)
- Organize tasks in customizable columns (Backlog, In Progress, Done + custom)
- Drag-and-drop tasks between columns and reorder within columns
- Define task dependencies (Task B waits for Task A to complete)
- Execute tasks that automatically create and monitor sandboxes
- View live terminal thumbnails on running task cards

## Architecture

```
KanbanBoardView / KanbanColumnView / KanbanTaskCardView
                    |
              KanbanStore (@MainActor @Observable)
               /         \
    KanbanPersistence    SbxServiceProtocol
     (JSON files)         (sandbox lifecycle)
```

### Data Flow

1. **User creates a task** → `KanbanStore.addTask()` → persists to JSON → view updates via `@Observable`
2. **User drags a task** → `KanbanStore.moveTask()` → updates column/sort order → persists → view updates
3. **User starts a task** → `KanbanStore.executeTask()` → `SbxServiceProtocol.run()` → sandbox created
4. **Sandbox status changes** → `ShellView.onChange(of: runningSandboxNames)` → `KanbanStore.syncSandboxStatus()` → task status updated
5. **Task completes** → `KanbanStore.checkAndExecuteDependents()` → dependent tasks auto-start

### Cross-Store Communication

The `KanbanStore` does not hold a reference to `SandboxStore` (per CLAUDE.md rules about `@Observable` cross-references). Instead, `ShellView` bridges them:

```swift
.onChange(of: runningSandboxNames) { _, _ in
    sessionStore.cleanupStaleSessions(sandboxes: sandboxStore.sandboxes)
    kanbanStore.syncSandboxStatus(sandboxes: sandboxStore.sandboxes)
}
```

## Data Model

### KanbanTask

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `title` | `String` | Task name |
| `description` | `String` | Optional description |
| `prompt` | `String` | Agent instruction sent via `sendMessage` |
| `agent` | `String` | Agent type (claude, codex, copilot, etc.) |
| `workspace` | `String` | Directory path for the sandbox |
| `columnID` | `String` | Which column this task belongs to |
| `sortOrder` | `Int` | Position within column |
| `sandboxName` | `String?` | Linked sandbox name (nil until executed) |
| `dependencyIDs` | `[String]` | Task IDs that must complete first |
| `status` | `KanbanTaskStatus` | pending, blocked, creating, running, completed, failed, cancelled |
| `createdAt` | `Date` | Creation timestamp |
| `completedAt` | `Date?` | Completion timestamp |

### KanbanColumn

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `title` | `String` | Column header |
| `sortOrder` | `Int` | Left-to-right position |
| `isDefault` | `Bool` | Prevents deletion (Backlog, In Progress, Done) |

### KanbanBoard

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID |
| `name` | `String` | Board name |
| `columns` | `[KanbanColumn]` | Ordered columns |
| `tasks` | `[KanbanTask]` | All tasks on this board |
| `createdAt` | `Date` | Creation timestamp |
| `updatedAt` | `Date` | Last modification timestamp |

## Persistence

- **Location**: `~/Library/Application Support/sbx-ui/kanban/{board-id}.json`
- **Strategy**: Atomic JSON file writes (`Data.write(to:options:.atomic)`)
- **Encoding**: ISO 8601 dates, pretty-printed, sorted keys
- **Loading**: All `.json` files in the directory are loaded on store init

No CoreData or SwiftData — JSON persistence is consistent with the CLI-centric architecture and avoids schema migration complexity.

## Dependency Engine

Dependencies form a directed acyclic graph (DAG) stored as `task.dependencyIDs: [String]`.

### Cycle Detection

Before adding a dependency, a DFS walk from the proposed target through its own dependencies checks whether the source task is reachable. If so, the dependency is rejected.

### Auto-Execution

When a task completes:
1. Scan all tasks whose `dependencyIDs` contain the completed task
2. For each, check if **all** dependencies are now completed
3. If so, auto-start the task via `executeTask()`

### Status Updates

- Tasks with unresolved dependencies are marked `.blocked`
- When dependencies complete, blocked tasks transition to `.pending`
- The `updateBlockedStatus()` method recalculates after any dependency change

## Drag-and-Drop

Uses SwiftUI's `.draggable()` and `.dropDestination(for:)` modifiers (macOS 13+):

- **Transfer type**: `String` (task ID) — lightweight, avoids serializing the full task
- **Column-level drop targets**: Each column accepts dropped task IDs
- **Insertion index**: Calculated from drop location Y coordinate relative to card heights
- **Visual feedback**: Column border highlights when targeted, dragged card reduces opacity

## View Hierarchy

```
KanbanBoardView
├── Toolbar (board name, rename, add column)
├── ScrollView (.horizontal)
│   └── HStack
│       └── ForEach(columns)
│           └── KanbanColumnView
│               ├── Column header (title, count, add task button)
│               └── ScrollView (.vertical)
│                   └── LazyVStack
│                       └── ForEach(tasks)
│                           └── KanbanTaskCardView
│                               ├── Title + status chip
│                               ├── Agent + workspace
│                               ├── Prompt preview (2 lines)
│                               ├── Terminal thumbnail (if running)
│                               ├── KanbanDependencyBadge
│                               └── Action buttons (start/cancel/delete)
└── Sheets
    ├── KanbanTaskDetailSheet (create/edit task)
    ├── Add Column sheet
    └── Rename Board sheet
```

## Task Execution Flow

```
User clicks "Start"
       │
       ▼
KanbanStore.executeTask()
       │
       ├── Check dependencies met
       │     (reject if unresolved)
       │
       ├── Set status → .creating
       │
       ├── service.run(agent, workspace, opts)
       │     └── Creates sandbox via sbx CLI
       │
       ├── Set sandboxName, status → .running
       │   Move to "In Progress" column
       │
       └── service.sendMessage(name, prompt)
             └── Sends agent instruction

         ┌─────────────────────────┐
         │  Existing 3-second poll │
         │  (SandboxStore)         │
         └──────────┬──────────────┘
                    │
                    ▼
         ShellView.onChange(of: runningSandboxNames)
                    │
                    ▼
         KanbanStore.syncSandboxStatus()
                    │
                    ├── sandbox .running → task .running
                    ├── sandbox .stopped → task .completed
                    │                      → move to "Done"
                    └── sandbox removed  → task .completed
                                           │
                                           ▼
                              checkAndExecuteDependents()
                                           │
                                           └── Start ready tasks
```

## Files

### New Files

| File | Purpose |
|------|---------|
| `sbx-ui/Models/KanbanTypes.swift` | KanbanTask, KanbanColumn, KanbanBoard, KanbanTaskStatus |
| `sbx-ui/Services/KanbanPersistence.swift` | JSON file persistence |
| `sbx-ui/Stores/KanbanStore.swift` | @MainActor @Observable store with full CRUD, DnD, dependency engine, execution |
| `sbx-ui/Views/Kanban/KanbanBoardView.swift` | Main board layout with toolbar and sheets |
| `sbx-ui/Views/Kanban/KanbanColumnView.swift` | Column with drop target and card list |
| `sbx-ui/Views/Kanban/KanbanTaskCardView.swift` | Task card with status, agent, prompt, thumbnail, actions |
| `sbx-ui/Views/Kanban/KanbanTaskDetailSheet.swift` | Create/edit task form with dependency picker |
| `sbx-ui/Views/Kanban/KanbanDependencyBadge.swift` | Dependency count and resolution indicator |

### Modified Files

| File | Change |
|------|--------|
| `sbx-ui/Views/ShellView.swift` | Added `.kanban` to `SidebarDestination`, routing, sandbox sync |
| `sbx-ui/Views/SidebarView.swift` | Added KANBAN sidebar entry |
| `sbx-ui/sbx_uiApp.swift` | KanbanStore creation and environment injection |

## Accessibility Identifiers

| Identifier | Element |
|------------|---------|
| `kanbanBoard` | Board container |
| `kanbanColumn-{id}` | Column container |
| `kanbanTaskCard-{id}` | Task card |
| `addTaskButton-{id}` | Add task button per column |
| `addColumnButton` | Add column button |
| `createBoardButton` | Create board button (empty state) |
| `taskTitleField` | Task title input |
| `taskDescriptionField` | Task description input |
| `taskPromptField` | Agent prompt input |
| `taskAgentPicker` | Agent selection picker |
| `taskWorkspaceField` | Workspace path input |
| `taskBrowseButton` | Workspace directory picker |
| `saveTaskButton` | Save/create task button |
| `startTaskButton-{id}` | Start task execution |
| `cancelTaskButton-{id}` | Cancel running task |
| `deleteTaskButton-{id}` | Delete task |
| `columnNameField` | New column name input |
| `submitColumnButton` | Submit new column |

## Design Decisions

1. **JSON persistence over SwiftData**: Simpler, no schema migrations, consistent with CLI-centric architecture. Acceptable for the expected scale (tens to low hundreds of tasks per board).

2. **Loose coupling via sandbox name string**: Tasks reference sandboxes by name, not by holding `Sandbox` objects. Avoids the cross-`@Observable` reference bug documented in CLAUDE.md.

3. **No separate polling loop**: Piggybacks on existing `SandboxStore.fetchSandboxes()` 3-second cycle. Adding another timer would be wasteful and cause consistency issues.

4. **Pure SwiftUI drag-and-drop**: Uses `.draggable()`/`.dropDestination()` rather than `NSViewRepresentable`. Maintains the app's 100% SwiftUI consistency.

5. **Single-board default**: Board is auto-created on first use. Multi-board support is a future enhancement.

## Future Enhancements

- Visual dependency lines between cards (Canvas/Path drawing)
- Diff visualization for sandbox code changes (`sbx exec git diff`)
- Board templates with pre-configured column layouts
- Multi-board picker and management
- Keyboard shortcuts for task management
- Export/import boards as JSON
