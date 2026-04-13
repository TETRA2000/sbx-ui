// LinuxShims.swift — Provides stubs for macOS-only symbols when building
// under SPM on Linux. This file is only compiled when SBX_SPM is defined
// (see Package.swift swiftSettings).

#if SBX_SPM
import Foundation

// MARK: - appLog shim

/// Minimal log-level enum matching LogStore.Entry.Level cases used by
/// CliExecutor (.error, .debug, .info, .warn).
enum _AppLogLevel: String, Sendable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
}

/// Drop-in replacement for the @MainActor appLog defined in LogStore.swift.
/// On Linux CLI builds we simply write to stderr.
nonisolated func appLog(
    _ level: _AppLogLevel,
    _ category: String,
    _ message: String,
    detail: String? = nil
) {
    #if DEBUG
    let prefix: String
    switch level {
    case .error: prefix = "ERROR"
    case .warn:  prefix = "WARN"
    case .info:  prefix = "INFO"
    case .debug: prefix = "DEBUG"
    }
    var line = "[\(prefix)] [\(category)] \(message)"
    if let detail = detail, !detail.isEmpty {
        line += " | \(detail)"
    }
    // Use FileHandle to avoid direct access to C stderr global (Swift 6 concurrency)
    FileHandle.standardError.write(Data((line + "\n").utf8))
    #endif
}
#endif
