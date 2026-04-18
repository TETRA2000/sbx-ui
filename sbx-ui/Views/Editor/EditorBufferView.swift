import SwiftUI
import AppKit

/// Wraps a plain NSTextView as the text-editing surface. The decision to
/// avoid the `CodeEditorView` SPM dependency for MVP keeps the surface swap
/// isolated to this one file — a later spec can introduce syntax highlighting
/// without touching the rest of the editor.
struct EditorBufferView: NSViewRepresentable {
    let sandboxName: String
    let tabID: UUID
    let initialContents: String
    let readOnly: Bool
    let loading: Bool
    let store: EditorStore

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.drawsBackground = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = !readOnly && !loading
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = NSColor(red: 0x0E / 255.0, green: 0x0E / 255.0, blue: 0x0E / 255.0, alpha: 1)
        textView.drawsBackground = true
        textView.allowsUndo = true
        textView.string = initialContents
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("editorBuffer")

        // Register buffer-pull callback with the store so save() can read current
        // buffer contents without going through a notification flight.
        store.registerBufferPull(sandboxName: sandboxName, tabID: tabID) { [weak textView] in
            let s = textView?.string ?? ""
            return Data(s.utf8)
        }

        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.isEditable = !readOnly && !loading
        if context.coordinator.lastLoadedTabID != tabID {
            // New tab — replace contents (fresh open).
            textView.string = initialContents
            context.coordinator.lastLoadedTabID = tabID
            store.registerBufferPull(sandboxName: sandboxName, tabID: tabID) { [weak textView] in
                let s = textView?.string ?? ""
                return Data(s.utf8)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.parent.store.unregisterBufferPull(tabID: coordinator.parent.tabID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorBufferView
        weak var textView: NSTextView?
        var lastLoadedTabID: UUID?

        init(_ parent: EditorBufferView) {
            self.parent = parent
            self.lastLoadedTabID = parent.tabID
        }

        func textDidChange(_ notification: Notification) {
            parent.store.onBufferMutated(sandboxName: parent.sandboxName, tabID: parent.tabID)
        }
    }
}
