import Foundation

// MARK: - ANSI Colors

enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case bold = "\u{001B}[1m"
    case dim = "\u{001B}[2m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case cyan = "\u{001B}[36m"
    case brightGreen = "\u{001B}[92m"
    case brightRed = "\u{001B}[91m"
}

private let useColor: Bool = {
    if ProcessInfo.processInfo.environment["NO_COLOR"] != nil { return false }
    if ProcessInfo.processInfo.environment["FORCE_COLOR"] != nil { return true }
    return isatty(STDOUT_FILENO) != 0
}()

func colored(_ text: String, _ codes: ANSIColor...) -> String {
    guard useColor else { return text }
    let prefix = codes.map(\.rawValue).joined()
    return "\(prefix)\(text)\(ANSIColor.reset.rawValue)"
}

func statusColored(_ status: String) -> String {
    switch status.lowercased() {
    case "running": return colored(status, .brightGreen)
    case "stopped": return colored(status, .dim)
    case "creating", "removing": return colored(status, .yellow)
    default: return status
    }
}

func decisionColored(_ decision: String) -> String {
    switch decision.lowercased() {
    case "allow": return colored(decision, .green)
    case "deny": return colored(decision, .red)
    default: return decision
    }
}

// MARK: - Table Printing

struct TableColumn {
    let header: String
    let colorize: ((String) -> String)?

    init(_ header: String, colorize: ((String) -> String)? = nil) {
        self.header = header
        self.colorize = colorize
    }
}

func printTable(columns: [TableColumn], rows: [[String]]) {
    guard !rows.isEmpty else {
        print(colored("  (none)", .dim))
        return
    }

    var widths = columns.map { $0.header.count }
    for row in rows {
        for (i, cell) in row.enumerated() where i < widths.count {
            widths[i] = max(widths[i], cell.count)
        }
    }
    widths = widths.map { $0 + 2 }

    // Header
    let header = columns.enumerated().map { (i, col) in
        colored(col.header.padding(toLength: widths[i], withPad: " ", startingAt: 0), .bold)
    }.joined()
    print(header)

    // Rows
    for row in rows {
        let line = row.enumerated().map { (i, cell) in
            let padded = cell.padding(toLength: widths[i], withPad: " ", startingAt: 0)
            if let colorize = columns[i].colorize {
                let coloredCell = colorize(cell)
                // Compensate for ANSI codes in padding
                let overhead = coloredCell.count - cell.count
                return coloredCell.padding(toLength: widths[i] + overhead, withPad: " ", startingAt: 0)
            }
            return padded
        }.joined()
        print(line)
    }
}

// MARK: - Message Helpers

func printSuccess(_ message: String) {
    print("\(colored("✓", .brightGreen)) \(message)")
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("\(colored("✗", .brightRed)) \(message)\n".utf8))
}

func printInfo(_ message: String) {
    print("\(colored("→", .cyan)) \(message)")
}

func printSection(_ title: String) {
    print()
    print(colored(title, .bold))
    print(colored(String(repeating: "─", count: title.count), .dim))
}
