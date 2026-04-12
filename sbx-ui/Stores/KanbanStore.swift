import Foundation
import SwiftUI

@MainActor @Observable final class KanbanStore {
    var boards: [KanbanBoard] = []
    var selectedBoardID: String?
    var error: String?
    var executingTaskIDs: Set<String> = []

    private let service: any SbxServiceProtocol

    var selectedBoard: KanbanBoard? {
        guard let id = selectedBoardID else { return boards.first }
        return boards.first { $0.id == id }
    }

    init(service: any SbxServiceProtocol) {
        self.service = service
        loadBoards()
    }

    // MARK: - Board CRUD

    func loadBoards() {
        do {
            boards = try KanbanPersistence.loadBoards()
            if let first = boards.first, selectedBoardID == nil {
                selectedBoardID = first.id
            }
        } catch {
            appLog(.error, "KanbanStore", "Failed to load boards", detail: error.localizedDescription)
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func createBoard(name: String) -> KanbanBoard {
        let board = KanbanBoard(name: name)
        boards.append(board)
        selectedBoardID = board.id
        save(board)
        appLog(.info, "KanbanStore", "Board created: \(name)")
        return board
    }

    func deleteBoard(id: String) {
        boards.removeAll { $0.id == id }
        if selectedBoardID == id {
            selectedBoardID = boards.first?.id
        }
        do {
            try KanbanPersistence.deleteBoard(id: id)
        } catch {
            appLog(.error, "KanbanStore", "Failed to delete board", detail: error.localizedDescription)
        }
    }

    func renameBoard(id: String, name: String) {
        guard let index = boardIndex(id) else { return }
        boards[index].name = name
        boards[index].updatedAt = Date()
        save(boards[index])
    }

    // MARK: - Column Management

    func addColumn(boardID: String, title: String) {
        guard let index = boardIndex(boardID) else { return }
        let maxOrder = boards[index].columns.map(\.sortOrder).max() ?? -1
        let column = KanbanColumn(title: title, sortOrder: maxOrder + 1)
        boards[index].columns.append(column)
        boards[index].updatedAt = Date()
        save(boards[index])
    }

    func removeColumn(boardID: String, columnID: String) {
        guard let index = boardIndex(boardID) else { return }
        guard let col = boards[index].columns.first(where: { $0.id == columnID }), !col.isDefault else { return }
        // Move tasks from removed column to first default column
        let fallbackID = boards[index].columns.first { $0.isDefault }?.id ?? ""
        for i in boards[index].tasks.indices where boards[index].tasks[i].columnID == columnID {
            boards[index].tasks[i].columnID = fallbackID
        }
        boards[index].columns.removeAll { $0.id == columnID }
        boards[index].updatedAt = Date()
        save(boards[index])
    }

    func renameColumn(boardID: String, columnID: String, title: String) {
        guard let bIndex = boardIndex(boardID),
              let cIndex = boards[bIndex].columns.firstIndex(where: { $0.id == columnID }) else { return }
        boards[bIndex].columns[cIndex].title = title
        boards[bIndex].updatedAt = Date()
        save(boards[bIndex])
    }

    // MARK: - Task CRUD

    @discardableResult
    func addTask(boardID: String, columnID: String, title: String, description: String = "",
                 prompt: String = "", agent: String = "claude", workspace: String = "") -> KanbanTask? {
        guard let index = boardIndex(boardID) else { return nil }
        let existingInColumn = boards[index].tasks(inColumn: columnID)
        let maxOrder = existingInColumn.map(\.sortOrder).max() ?? -1
        let task = KanbanTask(
            title: title, description: description, prompt: prompt,
            agent: agent, workspace: workspace,
            columnID: columnID, sortOrder: maxOrder + 1
        )
        boards[index].tasks.append(task)
        boards[index].updatedAt = Date()
        save(boards[index])
        appLog(.info, "KanbanStore", "Task added: \(title)")
        return task
    }

    func updateTask(boardID: String, task: KanbanTask) {
        guard let bIndex = boardIndex(boardID),
              let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == task.id }) else { return }
        boards[bIndex].tasks[tIndex] = task
        boards[bIndex].updatedAt = Date()
        save(boards[bIndex])
    }

    func removeTask(boardID: String, taskID: String) {
        guard let index = boardIndex(boardID) else { return }
        // Also remove this task from any dependency lists
        for i in boards[index].tasks.indices {
            boards[index].tasks[i].dependencyIDs.removeAll { $0 == taskID }
        }
        boards[index].tasks.removeAll { $0.id == taskID }
        boards[index].updatedAt = Date()
        save(boards[index])
    }

    // MARK: - Drag-and-Drop

    func moveTask(boardID: String, taskID: String, toColumnID: String, atIndex: Int) {
        guard let bIndex = boardIndex(boardID),
              let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

        boards[bIndex].tasks[tIndex].columnID = toColumnID

        // Recalculate sort orders for the target column
        var columnTasks = boards[bIndex].tasks(inColumn: toColumnID).filter { $0.id != taskID }
        let clampedIndex = min(atIndex, columnTasks.count)
        columnTasks.insert(boards[bIndex].tasks[tIndex], at: clampedIndex)

        for (order, task) in columnTasks.enumerated() {
            if let i = boards[bIndex].tasks.firstIndex(where: { $0.id == task.id }) {
                boards[bIndex].tasks[i].sortOrder = order
            }
        }

        boards[bIndex].updatedAt = Date()
        save(boards[bIndex])
    }

    // MARK: - Dependency Management

    func addDependency(boardID: String, taskID: String, dependsOn: String) -> Bool {
        guard let bIndex = boardIndex(boardID),
              let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        guard taskID != dependsOn else { return false }
        guard !boards[bIndex].tasks[tIndex].dependencyIDs.contains(dependsOn) else { return false }

        if wouldCreateCycle(board: boards[bIndex], taskID: taskID, dependsOn: dependsOn) {
            return false
        }

        boards[bIndex].tasks[tIndex].dependencyIDs.append(dependsOn)
        updateBlockedStatus(boardIndex: bIndex)
        boards[bIndex].updatedAt = Date()
        save(boards[bIndex])
        return true
    }

    func removeDependency(boardID: String, taskID: String, dependsOn: String) {
        guard let bIndex = boardIndex(boardID),
              let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        boards[bIndex].tasks[tIndex].dependencyIDs.removeAll { $0 == dependsOn }
        updateBlockedStatus(boardIndex: bIndex)
        boards[bIndex].updatedAt = Date()
        save(boards[bIndex])
    }

    func unresolvedDependencies(boardID: String, task: KanbanTask) -> [KanbanTask] {
        guard let board = boards.first(where: { $0.id == boardID }) else { return [] }
        return task.dependencyIDs.compactMap { depID in
            board.tasks.first { $0.id == depID && $0.status != .completed }
        }
    }

    // MARK: - Execution

    func executeTask(boardID: String, taskID: String) async {
        guard let bIndex = boardIndex(boardID),
              let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let task = boards[bIndex].tasks[tIndex]

        // Check dependencies are met
        let unresolved = unresolvedDependencies(boardID: boardID, task: task)
        if !unresolved.isEmpty {
            appLog(.warn, "KanbanStore", "Cannot execute task '\(task.title)': unresolved dependencies")
            return
        }

        executingTaskIDs.insert(taskID)
        boards[bIndex].tasks[tIndex].status = .creating
        save(boards[bIndex])

        do {
            let sandboxName = task.title.lowercased()
                .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
                .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let opts = RunOptions(name: sandboxName.isEmpty ? nil : sandboxName)
            let sandbox = try await service.run(agent: task.agent, workspace: task.workspace, opts: opts)

            if let tIdx = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                boards[bIndex].tasks[tIdx].sandboxName = sandbox.name
                boards[bIndex].tasks[tIdx].status = .running
                // Move to In Progress column
                if let inProgressCol = boards[bIndex].columns.first(where: { $0.title == "In Progress" }) {
                    boards[bIndex].tasks[tIdx].columnID = inProgressCol.id
                }
                save(boards[bIndex])
            }

            // Send the prompt if provided
            if !task.prompt.isEmpty {
                try? await service.sendMessage(name: sandbox.name, message: task.prompt)
            }

            appLog(.info, "KanbanStore", "Task '\(task.title)' started in sandbox '\(sandbox.name)'")
        } catch {
            if let tIdx = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) {
                boards[bIndex].tasks[tIdx].status = .failed
                save(boards[bIndex])
            }
            self.error = error.localizedDescription
            appLog(.error, "KanbanStore", "Task execution failed: \(task.title)", detail: error.localizedDescription)
        }

        executingTaskIDs.remove(taskID)
    }

    func cancelTask(boardID: String, taskID: String) async {
        guard let bIndex = boardIndex(boardID),
              let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = boards[bIndex].tasks[tIndex]
        if let name = task.sandboxName {
            try? await service.stop(name: name)
        }
        boards[bIndex].tasks[tIndex].status = .cancelled
        boards[bIndex].tasks[tIndex].completedAt = Date()
        boards[bIndex].updatedAt = Date()
        save(boards[bIndex])
        appLog(.info, "KanbanStore", "Task cancelled: \(task.title)")
    }

    // MARK: - Sandbox Status Sync

    func syncSandboxStatus(sandboxes: [Sandbox]) {
        for bIndex in boards.indices {
            var changed = false
            for tIndex in boards[bIndex].tasks.indices {
                guard let sbxName = boards[bIndex].tasks[tIndex].sandboxName else { continue }
                let task = boards[bIndex].tasks[tIndex]
                guard task.status == .running || task.status == .creating else { continue }

                if let sandbox = sandboxes.first(where: { $0.name == sbxName }) {
                    switch sandbox.status {
                    case .running where task.status != .running:
                        boards[bIndex].tasks[tIndex].status = .running
                        changed = true
                    case .stopped:
                        boards[bIndex].tasks[tIndex].status = .completed
                        boards[bIndex].tasks[tIndex].completedAt = Date()
                        if let doneCol = boards[bIndex].columns.first(where: { $0.title == "Done" }) {
                            boards[bIndex].tasks[tIndex].columnID = doneCol.id
                        }
                        changed = true
                    default:
                        break
                    }
                } else if task.status == .running {
                    // Sandbox was removed
                    boards[bIndex].tasks[tIndex].status = .completed
                    boards[bIndex].tasks[tIndex].completedAt = Date()
                    if let doneCol = boards[bIndex].columns.first(where: { $0.title == "Done" }) {
                        boards[bIndex].tasks[tIndex].columnID = doneCol.id
                    }
                    changed = true
                }
            }
            if changed {
                boards[bIndex].updatedAt = Date()
                save(boards[bIndex])
                // Check if newly completed tasks unblock dependents
                Task {
                    await checkAndExecuteDependents(boardID: boards[bIndex].id)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func boardIndex(_ id: String) -> Int? {
        boards.firstIndex { $0.id == id }
    }

    private func save(_ board: KanbanBoard) {
        do {
            try KanbanPersistence.saveBoard(board)
        } catch {
            appLog(.error, "KanbanStore", "Failed to save board", detail: error.localizedDescription)
        }
    }

    private func wouldCreateCycle(board: KanbanBoard, taskID: String, dependsOn: String) -> Bool {
        var visited = Set<String>()
        var stack = [dependsOn]
        while let current = stack.popLast() {
            if current == taskID { return true }
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            if let task = board.tasks.first(where: { $0.id == current }) {
                stack.append(contentsOf: task.dependencyIDs)
            }
        }
        return false
    }

    private func updateBlockedStatus(boardIndex bIndex: Int) {
        for tIndex in boards[bIndex].tasks.indices {
            let task = boards[bIndex].tasks[tIndex]
            guard task.status == .pending || task.status == .blocked else { continue }
            let hasUnresolved = task.dependencyIDs.contains { depID in
                boards[bIndex].tasks.first { $0.id == depID }?.status != .completed
            }
            boards[bIndex].tasks[tIndex].status = hasUnresolved ? .blocked : .pending
        }
    }

    private func checkAndExecuteDependents(boardID: String) async {
        guard let bIndex = boardIndex(boardID) else { return }
        let readyTasks = boards[bIndex].tasks.filter { task in
            task.status == .blocked &&
            task.dependencyIDs.allSatisfy { depID in
                boards[bIndex].tasks.first { $0.id == depID }?.status == .completed
            }
        }
        for task in readyTasks {
            if let tIndex = boards[bIndex].tasks.firstIndex(where: { $0.id == task.id }) {
                boards[bIndex].tasks[tIndex].status = .pending
            }
            await executeTask(boardID: boardID, taskID: task.id)
        }
    }
}
