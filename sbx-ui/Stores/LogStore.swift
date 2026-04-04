import Foundation
import os

/// Centralized log store that captures all internal events for the debug panel.
@MainActor @Observable final class LogStore {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        let detail: String?

        enum Level: String {
            case info = "INFO"
            case warn = "WARN"
            case error = "ERROR"
            case debug = "DEBUG"
        }
    }

    var entries: [Entry] = []
    var maxEntries = 500

    private let logger = Logger(subsystem: "com.sbx-ui", category: "App")

    func log(_ level: Entry.Level, category: String, _ message: String, detail: String? = nil) {
        let entry = Entry(timestamp: Date(), level: level, category: category, message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Also log to unified logging
        switch level {
        case .error: logger.error("[\(category)] \(message)")
        case .warn:  logger.warning("[\(category)] \(message)")
        case .info:  logger.info("[\(category)] \(message)")
        case .debug: logger.debug("[\(category)] \(message)")
        }
    }

    func info(_ category: String, _ message: String, detail: String? = nil) {
        log(.info, category: category, message, detail: detail)
    }

    func warn(_ category: String, _ message: String, detail: String? = nil) {
        log(.warn, category: category, message, detail: detail)
    }

    func error(_ category: String, _ message: String, detail: String? = nil) {
        log(.error, category: category, message, detail: detail)
    }

    func debug(_ category: String, _ message: String, detail: String? = nil) {
        log(.debug, category: category, message, detail: detail)
    }

    func clear() {
        entries.removeAll()
    }

    /// Shared instance for use from services that can't access SwiftUI environment.
    /// Initialized lazily on first access to avoid blocking app startup.
    private static var _shared: LogStore?
    static var shared: LogStore {
        if let s = _shared { return s }
        let s = LogStore()
        _shared = s
        return s
    }
}

/// Convenience global log functions for use throughout the app
@MainActor func appLog(_ level: LogStore.Entry.Level, _ category: String, _ message: String, detail: String? = nil) {
    LogStore.shared.log(level, category: category, message, detail: detail)
}
