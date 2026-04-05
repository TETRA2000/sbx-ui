import Foundation

@MainActor @Observable final class PolicyStore {
    var rules: [PolicyRule] = []
    var logEntries: [PolicyLogEntry] = []
    var logFilter: LogFilter = LogFilter()
    var loading: Bool = false
    var loadingLog: Bool = false
    var removingResources: Set<String> = []
    var error: String?

    struct LogFilter {
        var sandboxName: String?
        var blockedOnly: Bool = false
    }

    private let service: any SbxServiceProtocol

    init(service: any SbxServiceProtocol) {
        self.service = service
    }

    func fetchPolicies() async {
        loading = true
        defer { loading = false }
        do {
            rules = try await service.policyList()
            error = nil
        } catch {
            self.error = error.localizedDescription
            appLog(.error, "PolicyStore", "fetchPolicies failed", detail: error.localizedDescription)
        }
    }

    func addAllow(resources: String) async throws {
        appLog(.info, "PolicyStore", "Adding allow rule: \(resources)")
        _ = try await service.policyAllow(resources: resources)
        await fetchPolicies()
    }

    func addDeny(resources: String) async throws {
        appLog(.info, "PolicyStore", "Adding deny rule: \(resources)")
        _ = try await service.policyDeny(resources: resources)
        await fetchPolicies()
    }

    func removeRule(resource: String) async throws {
        removingResources.insert(resource)
        defer { removingResources.remove(resource) }
        try await service.policyRemove(resource: resource)
        await fetchPolicies()
    }

    func fetchLog(sandboxName: String? = nil) async {
        loadingLog = true
        defer { loadingLog = false }
        do {
            logEntries = try await service.policyLog(sandboxName: sandboxName)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    var filteredLog: [PolicyLogEntry] {
        var result = logEntries
        if let name = logFilter.sandboxName, !name.isEmpty {
            result = result.filter { $0.sandbox == name }
        }
        if logFilter.blockedOnly {
            result = result.filter { $0.blocked }
        }
        return result
    }
}
