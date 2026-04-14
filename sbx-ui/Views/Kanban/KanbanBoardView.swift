import SwiftUI

private struct TaskSheetContext: Identifiable {
    let id = UUID()
    let board: KanbanBoard
    let columnID: String
    let editingTask: KanbanTask?
}

struct KanbanBoardView: View {
    @Environment(KanbanStore.self) private var kanbanStore
    @Environment(SandboxStore.self) private var sandboxStore
    @Environment(TerminalSessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager
    var onViewSession: ((String) -> Void)?

    @State private var taskSheetContext: TaskSheetContext?
    @State private var showAddColumnSheet = false
    @State private var newColumnName = ""
    @State private var showRenameBoardSheet = false
    @State private var newBoardName = ""

    private var board: KanbanBoard? { kanbanStore.selectedBoard }

    var body: some View {
        VStack(spacing: 0) {
            if let board {
                // Toolbar
                HStack(spacing: 12) {
                    Text(board.name)
                        .font(.ui(18, weight: .bold))
                        .foregroundStyle(.white)

                    Button {
                        newBoardName = board.name
                        showRenameBoardSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        showAddColumnSheet = true
                    } label: {
                        Label {
                            Text("Add Column")
                                .font(.label(11))
                        } icon: {
                            Image(systemName: "plus.rectangle")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("addColumnButton")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                // Columns
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(board.sortedColumns) { column in
                            KanbanColumnView(
                                column: column,
                                board: board,
                                onAddTask: {
                                    taskSheetContext = TaskSheetContext(board: board, columnID: column.id, editingTask: nil)
                                },
                                onEditTask: { task in
                                    taskSheetContext = TaskSheetContext(board: board, columnID: task.columnID, editingTask: task)
                                },
                                onStartTask: { task in
                                    Task {
                                        await kanbanStore.executeTask(boardID: board.id, taskID: task.id)
                                        if let err = kanbanStore.error {
                                            toastManager.show(err)
                                            kanbanStore.error = nil
                                        }
                                    }
                                },
                                onCancelTask: { task in
                                    Task {
                                        await kanbanStore.cancelTask(boardID: board.id, taskID: task.id)
                                    }
                                },
                                onDeleteTask: { task in
                                    kanbanStore.removeTask(boardID: board.id, taskID: task.id)
                                },
                                onDropTask: { taskID, index in
                                    kanbanStore.moveTask(boardID: board.id, taskID: taskID, toColumnID: column.id, atIndex: index)
                                },
                                onViewSession: { task in
                                    if let sbxName = task.sandboxName,
                                       let sessionID = sessionStore.agentSessionID(for: sbxName) {
                                        onViewSession?(sessionID)
                                    }
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            } else {
                // No board: show creation prompt
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("No Kanban Board")
                        .font(.ui(18, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Create a board to start organizing your agent tasks")
                        .font(.ui(13))
                        .foregroundStyle(.tertiary)
                    Button("Create Board") {
                        kanbanStore.createBoard(name: "My Board")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .accessibilityIdentifier("createBoardButton")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.surface)
        .sheet(item: $taskSheetContext) { context in
            KanbanTaskDetailSheet(
                board: context.board,
                columnID: context.columnID,
                sandboxes: sandboxStore.sandboxes,
                existingTask: context.editingTask,
                onSave: { task in
                    if context.editingTask != nil {
                        kanbanStore.updateTask(boardID: context.board.id, task: task)
                        if let existing = context.editingTask {
                            let oldDeps = Set(existing.dependencyIDs)
                            let newDeps = Set(task.dependencyIDs)
                            for removed in oldDeps.subtracting(newDeps) {
                                kanbanStore.removeDependency(boardID: context.board.id, taskID: task.id, dependsOn: removed)
                            }
                            for added in newDeps.subtracting(oldDeps) {
                                _ = kanbanStore.addDependency(boardID: context.board.id, taskID: task.id, dependsOn: added)
                            }
                        }
                    } else {
                        if let created = kanbanStore.addTask(
                            boardID: context.board.id, columnID: context.columnID,
                            title: task.title, description: task.description,
                            prompt: task.prompt, agent: task.agent, workspace: task.workspace,
                            sandboxName: task.sandboxName
                        ) {
                            for depID in task.dependencyIDs {
                                _ = kanbanStore.addDependency(boardID: context.board.id, taskID: created.id, dependsOn: depID)
                            }
                        }
                    }
                    taskSheetContext = nil
                },
                onDismiss: {
                    taskSheetContext = nil
                }
            )
        }
        .sheet(isPresented: $showAddColumnSheet) {
            VStack(spacing: 16) {
                Text("Add Column")
                    .font(.ui(16, weight: .semibold))
                    .foregroundStyle(.white)
                TextField("Column name", text: $newColumnName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("columnNameField")
                HStack {
                    Button("Cancel") {
                        showAddColumnSheet = false
                        newColumnName = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Add") {
                        if let board, !newColumnName.trimmingCharacters(in: .whitespaces).isEmpty {
                            kanbanStore.addColumn(boardID: board.id, title: newColumnName.trimmingCharacters(in: .whitespaces))
                        }
                        showAddColumnSheet = false
                        newColumnName = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .disabled(newColumnName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("submitColumnButton")
                }
            }
            .padding(24)
            .frame(width: 320)
            .background(Color.surfaceContainer)
        }
        .sheet(isPresented: $showRenameBoardSheet) {
            VStack(spacing: 16) {
                Text("Rename Board")
                    .font(.ui(16, weight: .semibold))
                    .foregroundStyle(.white)
                TextField("Board name", text: $newBoardName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showRenameBoardSheet = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Rename") {
                        if let board, !newBoardName.trimmingCharacters(in: .whitespaces).isEmpty {
                            kanbanStore.renameBoard(id: board.id, name: newBoardName.trimmingCharacters(in: .whitespaces))
                        }
                        showRenameBoardSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 320)
            .background(Color.surfaceContainer)
        }
        .task {
            // Capture terminal snapshots for task card thumbnails
            while !Task.isCancelled {
                sessionStore.captureSnapshots()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
