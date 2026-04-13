import SwiftUI

struct KanbanTaskDetailSheet: View {
    let board: KanbanBoard
    let columnID: String
    let sandboxes: [Sandbox]
    var existingTask: KanbanTask?
    var onSave: (KanbanTask) -> Void
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var prompt: String = ""
    @State private var selectedSandboxName: String = ""
    @State private var selectedDependencyIDs: Set<String> = []

    private var isEditing: Bool { existingTask != nil }

    private var runningSandboxes: [Sandbox] {
        sandboxes.filter { $0.status == .running }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !selectedSandboxName.isEmpty
    }

    private var otherTasks: [KanbanTask] {
        board.tasks.filter { $0.id != existingTask?.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Task" : "New Task")
                    .font(.ui(16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title")
                            .font(.label(11))
                            .foregroundStyle(.secondary)
                        TextField("Task title", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("taskTitleField")
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.label(11))
                            .foregroundStyle(.secondary)
                        TextField("Optional description", text: $description, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("taskDescriptionField")
                    }

                    // Sandbox picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sandbox")
                            .font(.label(11))
                            .foregroundStyle(.secondary)
                        if runningSandboxes.isEmpty {
                            Text("No running sandboxes — deploy one from the Dashboard first")
                                .font(.ui(11))
                                .foregroundStyle(Color.surfaceContainerHighest)
                                .padding(.vertical, 6)
                        } else {
                            Picker("Sandbox", selection: $selectedSandboxName) {
                                Text("Select a sandbox…").tag("")
                                ForEach(runningSandboxes) { sandbox in
                                    HStack {
                                        Text(sandbox.name)
                                        Text("(\(sandbox.agent))")
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(sandbox.name)
                                }
                            }
                            .labelsHidden()
                            .accessibilityIdentifier("taskSandboxPicker")
                        }
                    }

                    // Prompt
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent Prompt")
                            .font(.label(11))
                            .foregroundStyle(.secondary)
                        TextField("Instructions for the agent", text: $prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("taskPromptField")
                    }

                    // Dependencies
                    if !otherTasks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dependencies")
                                .font(.label(11))
                                .foregroundStyle(.secondary)
                            Text("Tasks that must complete before this one starts")
                                .font(.ui(10))
                                .foregroundStyle(Color.surfaceContainerHighest)

                            ForEach(otherTasks) { depTask in
                                HStack(spacing: 8) {
                                    Image(systemName: selectedDependencyIDs.contains(depTask.id)
                                          ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedDependencyIDs.contains(depTask.id)
                                                         ? Color.accent : .secondary)
                                        .font(.system(size: 14))
                                    Text(depTask.title)
                                        .font(.ui(12))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(depTask.status.rawValue.uppercased())
                                        .font(.code(9))
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if selectedDependencyIDs.contains(depTask.id) {
                                        selectedDependencyIDs.remove(depTask.id)
                                    } else {
                                        selectedDependencyIDs.insert(depTask.id)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Create Task") {
                    let task = KanbanTask(
                        id: existingTask?.id ?? UUID().uuidString,
                        title: title.trimmingCharacters(in: .whitespaces),
                        description: description,
                        prompt: prompt,
                        columnID: existingTask?.columnID ?? columnID,
                        sortOrder: existingTask?.sortOrder ?? 0,
                        sandboxName: selectedSandboxName.isEmpty ? nil : selectedSandboxName,
                        dependencyIDs: Array(selectedDependencyIDs),
                        status: existingTask?.status ?? .pending,
                        createdAt: existingTask?.createdAt ?? Date(),
                        completedAt: existingTask?.completedAt
                    )
                    onSave(task)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
                .tint(Color.accent)
                .accessibilityIdentifier("saveTaskButton")
            }
            .padding()
        }
        .frame(minWidth: 480, maxWidth: 480, minHeight: 500)
        .background(Color.surfaceContainer)
        .onAppear {
            if let task = existingTask {
                title = task.title
                description = task.description
                prompt = task.prompt
                selectedSandboxName = task.sandboxName ?? ""
                selectedDependencyIDs = Set(task.dependencyIDs)
            } else if let first = runningSandboxes.first {
                selectedSandboxName = first.name
            }
        }
    }
}
