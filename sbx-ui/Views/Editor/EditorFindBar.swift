import SwiftUI

struct EditorFindBar: View {
    let sandboxName: String
    @Binding var isVisible: Bool
    @Binding var query: String
    @Binding var caseSensitive: Bool
    @Binding var wholeWord: Bool
    let matches: [Range<String.Index>]
    let currentIndex: Int
    let onNext: () -> Void
    let onPrev: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.code(12))
                .focused($focused)
                .accessibilityIdentifier("editorFindQuery")
                .onSubmit { onNext() }
            Text(matchCounterText)
                .font(.code(11))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("editorFindCounter")
            Button {
                onPrev()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityIdentifier("editorFindPrev")
            Button {
                onNext()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("g", modifiers: .command)
            .accessibilityIdentifier("editorFindNext")
            Toggle("Aa", isOn: $caseSensitive)
                .toggleStyle(.button)
                .controlSize(.mini)
                .font(.code(11))
                .accessibilityIdentifier("editorFindCaseToggle")
            Toggle("W", isOn: $wholeWord)
                .toggleStyle(.button)
                .controlSize(.mini)
                .font(.code(11))
                .accessibilityIdentifier("editorFindWholeWordToggle")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surfaceContainerHigh)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cornerRadius))
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .onAppear { focused = true }
        .accessibilityIdentifier("editorFindBar")
    }

    private var matchCounterText: String {
        if query.isEmpty { return "" }
        if matches.isEmpty { return "0/0" }
        return "\(currentIndex + 1)/\(matches.count)"
    }
}

/// Computes match ranges in the given text, respecting case-sensitive and
/// whole-word toggles. Kept out of the view so tests can call it directly.
enum EditorFindEngine {
    static func matches(in text: String, query: String, caseSensitive: Bool, wholeWord: Bool) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: query, options: options, range: searchStart..<text.endIndex) {
            if wholeWord {
                let beforeIsBoundary: Bool = {
                    guard range.lowerBound > text.startIndex else { return true }
                    let prev = text[text.index(before: range.lowerBound)]
                    return !prev.isLetter && !prev.isNumber && prev != "_"
                }()
                let afterIsBoundary: Bool = {
                    guard range.upperBound < text.endIndex else { return true }
                    let next = text[range.upperBound]
                    return !next.isLetter && !next.isNumber && next != "_"
                }()
                if beforeIsBoundary && afterIsBoundary { ranges.append(range) }
            } else {
                ranges.append(range)
            }
            searchStart = range.upperBound
        }
        return ranges
    }
}
