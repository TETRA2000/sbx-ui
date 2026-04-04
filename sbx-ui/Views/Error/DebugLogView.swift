import SwiftUI

struct DebugLogView: View {
    @Environment(LogStore.self) private var logStore
    @State private var filterLevel: LogStore.Entry.Level?
    @State private var filterCategory: String?
    @State private var searchText = ""
    @State private var autoScroll = true

    private var filteredEntries: [LogStore.Entry] {
        logStore.entries.filter { entry in
            if let level = filterLevel, entry.level != level { return false }
            if let cat = filterCategory, entry.category != cat { return false }
            if !searchText.isEmpty {
                let text = searchText.lowercased()
                return entry.message.lowercased().contains(text)
                    || (entry.detail?.lowercased().contains(text) ?? false)
                    || entry.category.lowercased().contains(text)
            }
            return true
        }
    }

    private var categories: [String] {
        Array(Set(logStore.entries.map(\.category))).sorted()
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Text("Debug Log")
                    .font(.ui(14, weight: .semibold))

                Spacer()

                // Level filter
                Picker("Level", selection: $filterLevel) {
                    Text("All Levels").tag(nil as LogStore.Entry.Level?)
                    Text("ERROR").tag(LogStore.Entry.Level.error as LogStore.Entry.Level?)
                    Text("WARN").tag(LogStore.Entry.Level.warn as LogStore.Entry.Level?)
                    Text("INFO").tag(LogStore.Entry.Level.info as LogStore.Entry.Level?)
                    Text("DEBUG").tag(LogStore.Entry.Level.debug as LogStore.Entry.Level?)
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                // Category filter
                Picker("Category", selection: $filterCategory) {
                    Text("All").tag(nil as String?)
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                // Search
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .font(.ui(11))

                Text("\(filteredEntries.count)")
                    .font(.code(11))
                    .foregroundStyle(.secondary)

                Button {
                    logStore.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.surfaceContainer)

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                List(filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .id(entry.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .font(.code(11))
                .onChange(of: logStore.entries.count) {
                    if autoScroll, let last = filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.surfaceLowest)
    }
}

private struct LogEntryRow: View {
    let entry: LogStore.Entry
    @State private var expanded = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .foregroundStyle(.tertiary)
                    .frame(width: 85, alignment: .leading)

                Text(entry.level.rawValue)
                    .foregroundStyle(levelColor)
                    .frame(width: 40, alignment: .leading)

                Text(entry.category)
                    .foregroundStyle(Color.accent)
                    .frame(width: 80, alignment: .leading)

                Text(entry.message)
                    .foregroundStyle(.primary)
                    .lineLimit(expanded ? nil : 1)

                Spacer()

                if entry.detail != nil {
                    Button {
                        expanded.toggle()
                    } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if expanded, let detail = entry.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 211) // align with message column
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 1)
    }

    private var levelColor: Color {
        switch entry.level {
        case .error: .error
        case .warn: Color.orange
        case .info: .secondary
        case .debug: Color.gray
        }
    }
}
