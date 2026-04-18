import Foundation
import Testing
@testable import sbx_ui

// MARK: - Shared fixtures

@MainActor
private func makeStore() -> (store: EditorStore, provider: FakeEditorDocumentProvider, toast: ToastManager) {
    let provider = FakeEditorDocumentProvider()
    let toast = ToastManager()
    let store = EditorStore(provider: provider, toastManager: toast)
    return (store, provider, toast)
}

private func sandbox(name: String = "claude-project", workspace: String = "/ws") -> Sandbox {
    Sandbox(id: UUID().uuidString, name: name, agent: "claude", status: .running,
            workspace: workspace, ports: [], createdAt: Date())
}

private let root = URL(fileURLWithPath: "/ws")

// MARK: - Tab open / classification

@MainActor
struct EditorStoreOpenTests {
    @Test func openFile_new_addsEditableTab() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/README.md")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "hello")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabs = await store.workspaces[sbx.name]?.tabs ?? []
        #expect(tabs.count == 1)
        #expect(tabs.first?.path == file.standardizedFileURL)
        if case .editable = tabs.first?.status {} else {
            Issue.record("Expected .editable, got \(String(describing: tabs.first?.status))")
        }
    }

    @Test func openFile_tooLarge_opensInTooLargeStatus() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/huge.bin")
        await provider.seedDirectory(root)
        await provider.seedFile(file, contents: Data(repeating: 0x41, count: Int(EditorStore.hardSizeCap) + 1))
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tab = await store.workspaces[sbx.name]?.tabs.first
        if case .tooLarge = tab?.status {} else {
            Issue.record("Expected .tooLarge, got \(String(describing: tab?.status))")
        }
    }

    @Test func openFile_readOnly_whenAboveSoftCap() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/big.txt")
        // Build a file larger than 2 MB of UTF-8 'a'.
        let payload = Data(repeating: 0x61, count: Int(EditorStore.softSizeCap) + 1)
        await provider.seedDirectory(root)
        await provider.seedFile(file, contents: payload)
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tab = await store.workspaces[sbx.name]?.tabs.first
        #expect(tab?.status == .readOnly)
    }

    @Test func openFile_binary_showsBinaryNotice() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/binary.bin")
        // Invalid UTF-8: lone continuation byte.
        await provider.seedDirectory(root)
        await provider.seedFile(file, contents: Data([0xC3, 0x28]))
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tab = await store.workspaces[sbx.name]?.tabs.first
        #expect(tab?.status == .binary)
    }

    @Test func openFile_outOfScope_doesNotAddTab() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/etc/passwd")
        await provider.seedDirectory(root)
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabs = await store.workspaces[sbx.name]?.tabs ?? []
        #expect(tabs.isEmpty)
    }

    @Test func openFile_rePath_focusesExistingTab() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "hello")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabs = await store.workspaces[sbx.name]?.tabs ?? []
        #expect(tabs.count == 1)
    }
}

// MARK: - Tab lifecycle

@MainActor
struct EditorStoreTabLifecycleTests {
    @Test func activateTab_byIndex_switchesActive() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        await provider.seedDirectory(root)
        let a = URL(fileURLWithPath: "/ws/a.txt")
        let b = URL(fileURLWithPath: "/ws/b.txt")
        await provider.seedFile(a, text: "A")
        await provider.seedFile(b, text: "B")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: a)
        await store.openFile(sandboxName: sbx.name, path: b)
        let firstID = await store.workspaces[sbx.name]?.tabs.first?.id
        await store.activateTab(sandboxName: sbx.name, index: 1)
        let active = await store.workspaces[sbx.name]?.activeTabID
        #expect(active == firstID)
    }

    @Test func closeTab_clean_closesImmediately() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "A")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        let result = await store.closeTab(sandboxName: sbx.name, tabID: tabID, force: false)
        if case .closed = result {} else {
            Issue.record("Expected .closed, got \(result)")
        }
        let count = await store.workspaces[sbx.name]?.tabs.count ?? -1
        #expect(count == 0)
    }

    @Test func closeTab_dirty_presentsConfirmation() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "A")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("modified".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        let result = await store.closeTab(sandboxName: sbx.name, tabID: tabID, force: false)
        if case .needsConfirmation = result {} else {
            Issue.record("Expected .needsConfirmation, got \(result)")
        }
        let hasPending = await store.pendingCloseConfirmation != nil
        #expect(hasPending)
    }

    @Test func closeTab_dirtyWithForce_discardsAndCloses() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "A")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("modified".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        let result = await store.closeTab(sandboxName: sbx.name, tabID: tabID, force: true)
        if case .closed = result {} else { Issue.record("Expected .closed") }
        let count = await store.workspaces[sbx.name]?.tabs.count ?? -1
        #expect(count == 0)
    }
}

// MARK: - Dirty pipeline

@MainActor
struct EditorStoreDirtyPipelineTests {
    @Test func onBufferMutated_setsTentativelyDirty() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("v2".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        let tab = await store.workspaces[sbx.name]?.tabs.first
        #expect(tab?.tentativelyDirty == true)
    }

    @Test func dirtyTabsSummary_reconcilesWithinDebounceWindow() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("different".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        let summary = await store.dirtyTabsSummary()
        #expect(summary.count == 1)
        #expect(summary.first?.path == file.standardizedFileURL)
    }

    @Test func revertToOriginal_clearsDirtyOnDebounce() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        // Buffer equals saved contents → fingerprint match.
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("v1".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        // Wait past 500 ms debounce.
        try? await Task.sleep(nanoseconds: 700_000_000)
        let tab = await store.workspaces[sbx.name]?.tabs.first
        #expect(tab?.tentativelyDirty == false)
    }

    @Test func closeTab_cancelsPendingDebounce() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("v2".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        _ = await store.closeTab(sandboxName: sbx.name, tabID: tabID, force: true)
        // Wait past debounce — should be no-op since task was cancelled.
        try? await Task.sleep(nanoseconds: 700_000_000)
        let count = await store.workspaces[sbx.name]?.tabs.count ?? -1
        #expect(count == 0)
    }
}

// MARK: - Save flow

@MainActor
struct EditorStoreSaveTests {
    @Test func save_success_clearsDirtyAndFlashes() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("v2".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        let result = await store.save(sandboxName: sbx.name, tabID: tabID)
        if case .saved = result {} else { Issue.record("Expected .saved, got \(result)") }
        let tab = await store.workspaces[sbx.name]?.tabs.first
        #expect(tab?.tentativelyDirty == false)
        // Bytes persisted exactly.
        let written = try? await provider.readFile(at: file)
        #expect(written == Data("v2".utf8))
    }

    @Test func save_failure_keepsDirtyAndToasts() async {
        let (store, provider, toast) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("v2".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        await provider.setFailWrite(NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: "permission denied"]))
        let result = await store.save(sandboxName: sbx.name, tabID: tabID)
        if case .failed = result {} else { Issue.record("Expected .failed, got \(result)") }
        #expect(toast.toasts.count == 1)
        let tab = await store.workspaces[sbx.name]?.tabs.first
        #expect(tab?.tentativelyDirty == true)
    }

    @Test func save_externalChange_presentsDialog() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        let tabID = await store.workspaces[sbx.name]?.tabs.first?.id ?? UUID()
        await store.registerBufferPull(sandboxName: sbx.name, tabID: tabID) { Data("v2".utf8) }
        await store.onBufferMutated(sandboxName: sbx.name, tabID: tabID)
        // Simulate external change: bump mtime in the fake provider.
        await provider.advanceMtime(file)
        let result = await store.save(sandboxName: sbx.name, tabID: tabID)
        if case .externalChange = result {} else { Issue.record("Expected .externalChange, got \(result)") }
        let hasPending = await store.pendingExternalChange != nil
        #expect(hasPending)
    }
}

// MARK: - Classification helper

@MainActor
struct EditorStoreClassificationTests {
    @Test func classifyFile_underSoftCap_isEditable() {
        #expect(EditorStore.classifyFile(size: 1024) == .editable)
    }

    @Test func classifyFile_atSoftCap_isEditable() {
        #expect(EditorStore.classifyFile(size: EditorStore.softSizeCap) == .editable)
    }

    @Test func classifyFile_justAboveSoftCap_isReadOnly() {
        #expect(EditorStore.classifyFile(size: EditorStore.softSizeCap + 1) == .readOnly)
    }

    @Test func classifyFile_justAboveHardCap_isTooLarge() {
        #expect(EditorStore.classifyFile(size: EditorStore.hardSizeCap + 1) == .tooLarge)
    }
}

// MARK: - Sandbox status sync

@MainActor
struct EditorStoreSandboxSyncTests {
    @Test func syncSandboxStatus_stoppedSandbox_preservesState() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        // Transition to stopped — sandbox is still in the list, just not running.
        let stopped = Sandbox(id: sbx.id, name: sbx.name, agent: sbx.agent, status: .stopped,
                              workspace: sbx.workspace, ports: [], createdAt: sbx.createdAt)
        await store.syncSandboxStatus(sandboxes: [stopped])
        let tabs = await store.workspaces[sbx.name]?.tabs ?? []
        #expect(tabs.count == 1)
    }

    @Test func syncSandboxStatus_removedSandbox_garbageCollects() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        let file = URL(fileURLWithPath: "/ws/a.txt")
        await provider.seedDirectory(root)
        await provider.seedFile(file, text: "v1")
        await store.open(sandbox: sbx)
        await store.openFile(sandboxName: sbx.name, path: file)
        await store.syncSandboxStatus(sandboxes: []) // removed entirely
        let exists = await store.workspaces[sbx.name] != nil
        #expect(!exists)
    }
}

// MARK: - 20-tab warning

@MainActor
struct EditorStoreTabLimitTests {
    @Test func exceedingLimit_triggersWarning_andDoesNotAddTab() async {
        let (store, provider, _) = await makeStore()
        let sbx = sandbox()
        await provider.seedDirectory(root)
        for i in 0..<EditorStore.maxOpenTabs {
            let f = URL(fileURLWithPath: "/ws/f\(i).txt")
            await provider.seedFile(f, text: "x")
        }
        let extra = URL(fileURLWithPath: "/ws/extra.txt")
        await provider.seedFile(extra, text: "x")
        await store.open(sandbox: sbx)
        for i in 0..<EditorStore.maxOpenTabs {
            await store.openFile(sandboxName: sbx.name, path: URL(fileURLWithPath: "/ws/f\(i).txt"))
        }
        #expect((await store.workspaces[sbx.name]?.tabs.count ?? 0) == EditorStore.maxOpenTabs)
        await store.openFile(sandboxName: sbx.name, path: extra)
        #expect((await store.workspaces[sbx.name]?.tabs.count ?? 0) == EditorStore.maxOpenTabs)
        #expect(store.showTabLimitWarning == true)
    }
}

// MARK: - Layout + pane visibility

@MainActor
struct EditorStoreLayoutTests {
    @Test func setLayoutRatio_clampsToSafeRange() async {
        let (store, _, _) = await makeStore()
        let sbx = sandbox()
        await store.open(sandbox: sbx)
        await store.setLayoutRatio(-0.1, for: sbx.name)
        #expect((await store.workspaces[sbx.name]?.layoutRatio ?? -1) == 0.1)
        await store.setLayoutRatio(1.5, for: sbx.name)
        #expect((await store.workspaces[sbx.name]?.layoutRatio ?? -1) == 0.9)
    }

    @Test func setPaneVisibility_preventsBothCollapsed() async {
        let (store, _, _) = await makeStore()
        let sbx = sandbox()
        await store.open(sandbox: sbx)
        await store.setPaneVisibility(PaneVisibility(editorVisible: false, terminalVisible: false), for: sbx.name)
        let vis = await store.paneVisibility(for: sbx.name)
        #expect(vis.editorVisible || vis.terminalVisible)
    }
}
