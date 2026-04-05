import AppIntents

struct SbxShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateSandboxIntent(),
            phrases: ["Create a sandbox in \(.applicationName)"],
            shortTitle: "Create Sandbox",
            systemImageName: "plus.rectangle"
        )
        AppShortcut(
            intent: StopSandboxIntent(),
            phrases: ["Stop sandbox in \(.applicationName)"],
            shortTitle: "Stop Sandbox",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ListSandboxesIntent(),
            phrases: ["List my sandboxes in \(.applicationName)"],
            shortTitle: "List Sandboxes",
            systemImageName: "list.bullet"
        )
    }
}
