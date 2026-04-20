import ArgumentParser
import SBXCore
import Foundation

@main
struct SbxUI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sbx-ui",
        abstract: "CLI for Docker Sandbox management",
        version: "0.1.0",
        subcommands: [
            Ls.self,
            Create.self,
            Stop.self,
            Rm.self,
            Run.self,
            Exec.self,
            Policy.self,
            Ports.self,
            Env.self,
            Status.self,
        ],
        defaultSubcommand: Ls.self
    )
}
