import ArgumentParser
import SBXCore
import Foundation

// MARK: - Shared Options

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Output in JSON format")
    var json = false
}

// MARK: - Helper

func makeService() -> RealSbxService {
    return RealSbxService()
}

// MARK: - ls

struct Ls: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List sandboxes"
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        let sandboxes = try await svc.list()

        if output.json {
            let data = sandboxes.map { s in
                [
                    "name": s.name,
                    "agent": s.agent,
                    "status": s.status.rawValue,
                    "workspace": s.workspace,
                ] as [String: String]
            }
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "[]")
            return
        }

        if sandboxes.isEmpty {
            printInfo("No sandboxes found. Create one with: sbx-ui create <workspace>")
            return
        }

        let rows = sandboxes.map { s -> [String] in
            let portsStr = s.ports.map {
                "\($0.hostPort)->\($0.sandboxPort)/\($0.protocolType)"
            }.joined(separator: ", ")
            return [s.name, s.agent, s.status.rawValue, portsStr, s.workspace]
        }

        printTable(
            columns: [
                TableColumn("SANDBOX"),
                TableColumn("AGENT"),
                TableColumn("STATUS", colorize: statusColored),
                TableColumn("PORTS"),
                TableColumn("WORKSPACE"),
            ],
            rows: rows
        )
    }
}

// MARK: - create

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new sandbox"
    )

    @Argument(help: "Workspace path to mount")
    var workspace: String

    @Option(name: [.short, .long], help: "Sandbox name")
    var name: String?

    @Option(name: [.short, .long], help: "Agent to use")
    var agent: String = "claude"

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        printInfo("Creating sandbox with agent '\(agent)' at \(workspace)...")

        let opts = RunOptions(name: name)
        let sandbox = try await svc.run(agent: agent, workspace: workspace, opts: opts)

        if output.json {
            let data: [String: String] = [
                "name": sandbox.name,
                "agent": sandbox.agent,
                "status": sandbox.status.rawValue,
                "workspace": sandbox.workspace,
            ]
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "{}")
        } else {
            printSuccess("Created sandbox '\(sandbox.name)'")
            print("  Workspace: \(sandbox.workspace)")
            print("  Agent: \(sandbox.agent)")
            print("  Status: \(statusColored(sandbox.status.rawValue))")
        }
    }
}

// MARK: - run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Attach to a sandbox interactively"
    )

    @Argument(help: "Sandbox name")
    var name: String

    func run() async throws {
        printInfo("Attaching to sandbox '\(name)'...")
        // Replace current process with sbx run
        let sbxPath = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").compactMap { dir -> String? in
                let path = "\(dir)/sbx"
                return FileManager.default.isExecutableFile(atPath: path) ? path : nil
            }.first ?? "sbx"
        let args = ["sbx", "run", name]
        // Convert to C strings for execvp
        let cArgs = args.map { strdup($0) } + [nil]
        execvp(sbxPath, cArgs)
        // If execvp returns, it failed
        cArgs.compactMap { $0 }.forEach { free($0) }
        throw SbxServiceError.cliError("Failed to exec sbx run")
    }
}

// MARK: - stop

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop a sandbox"
    )

    @Argument(help: "Sandbox name")
    var name: String

    func run() async throws {
        let svc = makeService()
        try await svc.stop(name: name)
        printSuccess("Stopped sandbox '\(name)'")
    }
}

// MARK: - rm

struct Rm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a sandbox"
    )

    @Argument(help: "Sandbox name")
    var name: String

    func run() async throws {
        let svc = makeService()
        try await svc.rm(name: name)
        printSuccess("Removed sandbox '\(name)'")
    }
}

// MARK: - exec

struct Exec: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute a command in a sandbox"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @Argument(help: "Command to execute")
    var command: String

    @Argument(parsing: .captureForPassthrough, help: "Command arguments")
    var args: [String] = []

    func run() async throws {
        let svc = makeService()
        let result = try await svc.exec(name: name, command: command, args: args)
        if !result.stdout.isEmpty {
            print(result.stdout, terminator: "")
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }
    }
}

// MARK: - status

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show detailed status of a sandbox"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        let sandboxes = try await svc.list()
        guard let sandbox = sandboxes.first(where: { $0.name == name }) else {
            throw SbxServiceError.notFound(name)
        }

        if output.json {
            var data: [String: Any] = [
                "name": sandbox.name,
                "agent": sandbox.agent,
                "status": sandbox.status.rawValue,
                "workspace": sandbox.workspace,
                "ports": sandbox.ports.map { [
                    "host_port": $0.hostPort,
                    "sandbox_port": $0.sandboxPort,
                    "protocol": $0.protocolType,
                ] as [String: Any] },
            ]
            if sandbox.status == SandboxStatus.running {
                let envVars = try await svc.envVarList(name: name)
                data["env_vars"] = envVars.map { ["key": $0.key, "value": $0.value] }
            }
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "{}")
            return
        }

        printSection("Sandbox: \(sandbox.name)")
        print("  Agent:     \(sandbox.agent)")
        print("  Status:    \(statusColored(sandbox.status.rawValue))")
        print("  Workspace: \(sandbox.workspace)")

        if !sandbox.ports.isEmpty {
            print()
            print("  \(colored("Ports:", .bold))")
            for p in sandbox.ports {
                print("    \(p.hostPort) → \(p.sandboxPort)/\(p.protocolType)")
            }
        }

        if sandbox.status == SandboxStatus.running {
            let envVars = try await svc.envVarList(name: name)
            if !envVars.isEmpty {
                print()
                print("  \(colored("Environment Variables:", .bold))")
                for v in envVars {
                    print("    \(colored(v.key, .cyan))=\(v.value)")
                }
            }
        }
        print()
    }
}
