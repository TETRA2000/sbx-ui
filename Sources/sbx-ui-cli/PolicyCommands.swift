import ArgumentParser
import SBXCore
import Foundation

struct Policy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage network policies",
        subcommands: [
            PolicyLs.self,
            PolicyAllow.self,
            PolicyDeny.self,
            PolicyRm.self,
            PolicyLog.self,
        ]
    )
}

struct PolicyLs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "List network policies"
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        let rules = try await svc.policyList()

        if output.json {
            let data = rules.map { [
                "id": $0.id,
                "type": $0.type,
                "decision": $0.decision.rawValue,
                "resources": $0.resources,
            ] }
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "[]")
            return
        }

        if rules.isEmpty {
            printInfo("No network policies configured.")
            return
        }

        printTable(
            columns: [
                TableColumn("NAME"),
                TableColumn("TYPE"),
                TableColumn("DECISION", colorize: decisionColored),
                TableColumn("RESOURCES"),
            ],
            rows: rules.map { [$0.id, $0.type, $0.decision.rawValue, $0.resources] }
        )
    }
}

struct PolicyAllow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "allow",
        abstract: "Add network allow rule"
    )

    @Argument(help: "Domain pattern to allow")
    var resources: String

    func run() async throws {
        let svc = makeService()
        _ = try await svc.policyAllow(resources: resources)
        printSuccess("Policy added: \(colored("allow", .green)) network \(resources)")
    }
}

struct PolicyDeny: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deny",
        abstract: "Add network deny rule"
    )

    @Argument(help: "Domain pattern to deny")
    var resources: String

    func run() async throws {
        let svc = makeService()
        _ = try await svc.policyDeny(resources: resources)
        printSuccess("Policy added: \(colored("deny", .red)) network \(resources)")
    }
}

struct PolicyRm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a network policy"
    )

    @Argument(help: "Resource pattern to remove")
    var resources: String

    func run() async throws {
        let svc = makeService()
        try await svc.policyRemove(resource: resources)
        printSuccess("Policy removed: \(resources)")
    }
}

struct PolicyLog: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "View policy log"
    )

    @Argument(help: "Filter by sandbox name")
    var sandbox: String?

    @Flag(name: .long, help: "Show only blocked requests")
    var blocked = false

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        var entries = try await svc.policyLog(sandboxName: sandbox)

        if blocked {
            entries = entries.filter { $0.blocked }
        }

        if output.json {
            let data = entries.map { [
                "sandbox": $0.sandbox,
                "host": $0.host,
                "proxy": $0.proxy,
                "rule": $0.rule,
                "count": "\($0.count)",
                "blocked": $0.blocked ? "true" : "false",
            ] }
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "[]")
            return
        }

        if entries.isEmpty {
            printInfo("No policy log entries found.")
            return
        }

        let allowed = entries.filter { !$0.blocked }
        let blockedEntries = entries.filter { $0.blocked }

        let columns = [
            TableColumn("SANDBOX"),
            TableColumn("HOST"),
            TableColumn("PROXY"),
            TableColumn("RULE"),
            TableColumn("COUNT"),
        ]

        if !allowed.isEmpty {
            printSection("Allowed requests")
            printTable(
                columns: columns,
                rows: allowed.map { [$0.sandbox, $0.host, $0.proxy, $0.rule, "\($0.count)"] }
            )
        }

        if !blockedEntries.isEmpty {
            printSection("Blocked requests")
            printTable(
                columns: columns,
                rows: blockedEntries.map { [$0.sandbox, $0.host, $0.proxy, $0.rule, "\($0.count)"] }
            )
        }
    }
}
