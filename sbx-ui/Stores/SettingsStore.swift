import Foundation
import AppKit

@MainActor @Observable final class SettingsStore {
    var preferredTerminal: TerminalApp? {
        didSet {
            UserDefaults.standard.set(preferredTerminal?.rawValue, forKey: "preferredTerminal")
        }
    }
    var availableTerminals: [TerminalApp] = []

    init() {
        if let raw = UserDefaults.standard.string(forKey: "preferredTerminal") {
            self.preferredTerminal = TerminalApp(rawValue: raw)
        }
        detectTerminals()
    }

    private func detectTerminals() {
        var available: [TerminalApp] = [.terminal] // Always available
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.iterm.bundleIdentifier) != nil {
            available.append(.iterm)
        }
        availableTerminals = available
        if preferredTerminal == nil {
            preferredTerminal = .terminal
        }
    }
}
