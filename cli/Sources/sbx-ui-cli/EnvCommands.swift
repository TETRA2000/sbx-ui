import ArgumentParser
import SBXCore
import Foundation

struct Env: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage environment variables",
        subcommands: [
            EnvLs.self,
            EnvSet.self,
            EnvRm.self,
        ]
    )
}

struct EnvLs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List environment variables"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        let envVars = try await svc.envVarList(name: name)

        if output.json {
            let data = envVars.map { ["key": $0.key, "value": $0.value] }
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "[]")
            return
        }

        if envVars.isEmpty {
            printInfo("No managed environment variables for '\(name)'.")
            return
        }

        printTable(
            columns: [
                TableColumn("KEY", colorize: { colored($0, .cyan) }),
                TableColumn("VALUE"),
            ],
            rows: envVars.map { [$0.key, $0.value] }
        )
    }
}

struct EnvSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set an environment variable"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @Argument(help: "Variable name")
    var key: String

    @Argument(help: "Variable value")
    var value: String

    func run() async throws {
        guard SbxValidation.isValidEnvKey(key) else {
            throw SbxServiceError.cliError(
                "Invalid env var key '\(key)'. Must match [A-Za-z_][A-Za-z0-9_]*"
            )
        }
        let svc = makeService()
        // Read current vars, upsert, sync
        var current = try await svc.envVarList(name: name)
        current.removeAll { $0.key == key }
        current.append(EnvVar(key: key, value: value))
        try await svc.envVarSync(name: name, vars: current)
        printSuccess("Set \(colored(key, .cyan))=\(value)")
    }
}

struct EnvRm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove an environment variable"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @Argument(help: "Variable name to remove")
    var key: String

    func run() async throws {
        let svc = makeService()
        var current = try await svc.envVarList(name: name)
        current.removeAll { $0.key == key }
        try await svc.envVarSync(name: name, vars: current)
        printSuccess("Removed \(colored(key, .cyan))")
    }
}
