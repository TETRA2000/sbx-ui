import Foundation

/// Parsed output of `sbx version`. Populated by `SbxOutputParser.parseVersion`.
public struct SbxVersionInfo: Sendable, Equatable {
    public let client: String
    public let server: String?
    public let raw: String

    nonisolated public init(client: String, server: String? = nil, raw: String) {
        self.client = client
        self.server = server
        self.raw = raw
    }
}

public enum SbxCliCompatibilityStatus: String, Sendable {
    case compatible, olderThanVerified, newerThanVerified, unknown
}

/// Compares a detected `sbx` CLI version against the version sbx-ui was
/// last verified against. Informational only — never blocks an operation.
public enum SbxCliCompatibility {
    public static let verifiedVersion = "0.34.0"

    nonisolated public static func assess(_ rawVersion: String, verifiedVersion: String = verifiedVersion) -> SbxCliCompatibilityStatus {
        guard let detected = SemverLite(parsing: rawVersion),
              let verified = SemverLite(parsing: verifiedVersion) else { return .unknown }
        if detected == verified { return .compatible }
        return detected < verified ? .olderThanVerified : .newerThanVerified
    }
}

private struct SemverLite: Comparable, Equatable {
    let major: Int, minor: Int, patch: Int

    init?(parsing raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[s.startIndex..<dash]) }
        if let space = s.firstIndex(of: " ") { s = String(s[s.startIndex..<space]) }
        let parts = s.split(separator: ".")
        guard parts.count == 3, let ma = Int(parts[0]), let mi = Int(parts[1]), let pa = Int(parts[2]) else { return nil }
        major = ma
        minor = mi
        patch = pa
    }

    static func < (l: SemverLite, r: SemverLite) -> Bool {
        (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
    }
}
