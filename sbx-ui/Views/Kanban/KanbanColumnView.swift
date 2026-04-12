import SwiftUI

struct KanbanColumnView: View {
    let column: KanbanColumn
    let board: KanbanBoard
    var onAddTask: () -> Void
    var onEditTask: (KanbanTask) -> Void
    var onStartTask: (KanbanTask) -> Void
    var onCancelTask: (KanbanTask) -> Void
    var onDeleteTask: (KanbanTask) -> Void
    var onDropTask: (String, Int) -> Void

    @State private var isTargeted = false

    private var columnTasks: [KanbanTask] {
        board.tasks(inColumn: column.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column header
            HStack {
                Text(column.title)
                    .font(.label(12, weight: .semibold))
                    .foregroundStyle(.white)

                Text("\(columnTasks.count)")
                    .font(.code(10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Spacer()

                Button {
                    onAddTask()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addTaskButton-\(column.id)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .background(Color.surfaceContainerHigh)

            // Task cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(columnTasks) { task in
                        KanbanTaskCardView(
                            task: task,
                            board: board,
                            onEdit: { onEditTask(task) },
                            onStart: { onStartTask(task) },
                            onCancel: { onCancelTask(task) },
                            onDelete: { onDeleteTask(task) }
                        )
                        .draggable(task.id)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .fill(Color.surface)
                .stroke(isTargeted ? Color.accent.opacity(0.5) : Color.surfaceContainerHigh.opacity(0.5), lineWidth: 1)
        )
        .dropDestination(for: String.self) { droppedIDs, location in
            guard let taskID = droppedIDs.first else { return false }
            let insertIndex = calculateInsertIndex(from: location)
            onDropTask(taskID, insertIndex)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isTargeted = targeted
            }
        }
    }

    private func calculateInsertIndex(from location: CGPoint) -> Int {
        // Approximate: each card is ~120pt tall + 8pt spacing
        let cardHeight: CGFloat = 128
        let headerHeight: CGFloat = 45
        let adjustedY = max(0, location.y - headerHeight)
        let index = Int(adjustedY / cardHeight)
        return min(index, columnTasks.count)
    }
}
