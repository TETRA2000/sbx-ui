import ArgumentParser
import SBXCore
import Foundation

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check sbx CLI version compatibility"
    )

    @OptionGroup var output: OutputOptions

    func run() async throws {
        let svc = makeService()
        let info = try await svc.version()
        let status = SbxCliCompatibility.assess(info.client)

        if output.json {
            let data: [String: String] = [
                "client_version": info.client,
                "server_version": info.server ?? "",
                "verified_version": SbxCliCompatibility.verifiedVersion,
                "status": status.rawValue,
            ]
            let json = try JSONSerialization.data(
                withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            print(String(data: json, encoding: .utf8) ?? "{}")
            return
        }

        printSection("sbx CLI Compatibility")
        print("  Detected client:  \(info.client)")
        if let server = info.server {
            print("  Detected server:  \(server)")
        }
        print("  Verified against: \(SbxCliCompatibility.verifiedVersion)")
        switch status {
        case .compatible:
            printSuccess("Compatible")
        case .olderThanVerified:
            printInfo("Older than the version sbx-ui was verified against — some commands may not exist yet.")
        case .newerThanVerified:
            printInfo("Newer than the version sbx-ui was verified against — should still work, but watch for CLI changes.")
        case .unknown:
            printInfo("Could not determine compatibility (unrecognized version format).")
        }
    }
}
