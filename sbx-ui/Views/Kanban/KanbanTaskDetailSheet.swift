import SwiftUI
import AppKit

struct KanbanTaskDetailSheet: View {
    let board: KanbanBoard
    let columnID: String
    var existingTask: KanbanTask?
    var onSave: (KanbanTask) -> Void
    var onDismiss: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var prompt: String = ""
    @State private var agent: String = "claude"
    @State private var workspace: String = ""
    @State private var selectedDependencyIDs: Set<String> = []

    private let availableAgents = ["claude", "codex", "copilot", "docker-agent", "gemini", "kiro", "opencode", "shell"]

    private var isEditing: Bool { existingTask != nil }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
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

                    // Agent picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent")
                            .font(.label(11))
                            .foregroundStyle(.secondary)
                        Picker("Agent", selection: $agent) {
                            ForEach(availableAgents, id: \.self) { agentName in
                                Text(agentName).tag(agentName)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("taskAgentPicker")
                    }

                    // Workspace
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace")
                            .font(.label(11))
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Workspace path", text: $workspace)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("taskWorkspaceField")
                            Button("Browse") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    workspace = url.path
                                }
                            }
                            .accessibilityIdentifier("taskBrowseButton")
                        }
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
                        agent: agent,
                        workspace: workspace,
                        columnID: existingTask?.columnID ?? columnID,
                        sortOrder: existingTask?.sortOrder ?? 0,
                        sandboxName: existingTask?.sandboxName,
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
        .frame(width: 480, minHeight: 500)
        .background(Color.surfaceContainer)
        .onAppear {
            if let task = existingTask {
                title = task.title
                description = task.description
                prompt = task.prompt
                agent = task.agent
                workspace = task.workspace
                selectedDependencyIDs = Set(task.dependencyIDs)
            } else if ProcessInfo.processInfo.environment["SBX_CLI_MOCK"] == "1" {
                workspace = "/tmp/mock-project"
            }
        }
    }
}
