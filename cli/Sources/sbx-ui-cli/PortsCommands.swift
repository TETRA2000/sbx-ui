import ArgumentParser
import SBXCore
import Foundation

struct Ports: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage port forwarding",
        subcommands: [
            PortsLs.self,
            PortsPublish.self,
            PortsUnpublish.self,
        ]
    )
}

struct PortsLs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List published ports"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        let ports = try await svc.portsList(name: name)

        if output.json {
            let data = ports.map { [
                "host_port": $0.hostPort,
                "sandbox_port": $0.sandboxPort,
                "protocol": $0.protocolType,
            ] as [String: Any] }
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "[]")
            return
        }

        if ports.isEmpty {
            printInfo("No published ports for '\(name)'.")
            return
        }

        printTable(
            columns: [
                TableColumn("HOST IP"),
                TableColumn("HOST PORT"),
                TableColumn("SANDBOX PORT"),
                TableColumn("PROTOCOL"),
            ],
            rows: ports.map {
                ["127.0.0.1", "\($0.hostPort)", "\($0.sandboxPort)", $0.protocolType]
            }
        )
    }
}

private func parsePortSpec(_ spec: String) throws -> (host: Int, sandbox: Int) {
    let parts = spec.split(separator: ":")
    guard parts.count == 2,
          let host = Int(parts[0]),
          let sandbox = Int(parts[1]) else {
        throw SbxServiceError.cliError(
            "Invalid port spec '\(spec)'. Expected HOST_PORT:SANDBOX_PORT"
        )
    }
    return (host, sandbox)
}

struct PortsPublish: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Publish a port"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @Argument(help: "Port spec HOST_PORT:SANDBOX_PORT")
    var spec: String

    func run() async throws {
        let (host, sandbox) = try parsePortSpec(spec)
        let svc = makeService()
        _ = try await svc.portsPublish(name: name, hostPort: host, sbxPort: sandbox)
        printSuccess("Published 127.0.0.1:\(host) → \(sandbox)/tcp")
    }
}

struct PortsUnpublish: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unpublish",
        abstract: "Unpublish a port"
    )

    @Argument(help: "Sandbox name")
    var name: String

    @Argument(help: "Port spec HOST_PORT:SANDBOX_PORT")
    var spec: String

    func run() async throws {
        let (host, sandbox) = try parsePortSpec(spec)
        let svc = makeService()
        try await svc.portsUnpublish(name: name, hostPort: host, sbxPort: sandbox)
        printSuccess("Unpublished 127.0.0.1:\(host) → \(sandbox)/tcp")
    }
}
