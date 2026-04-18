import Foundation
import SwiftUI
import CryptoKit

// MARK: - Public result + value types

enum CloseResult: Sendable {
    case closed
    case cancelled
    case saveFailed([UUID])
    case needsConfirmation
}

enum SaveResult: Sendable {
    case saved
    case failed(NSError)
    case noChange
    case externalChange(FileStat)
}

enum ExternalChangeResult: Sendable {
    case unchanged
    case reloaded
    case conflict(stat: FileStat)
}

struct DirtyTabSummary: Sendable, Identifiable {
    let tabID: UUID
    let sandboxName: String
    let path: URL
    var id: UUID { tabID }
}

struct PaneVisibility: Sendable, Hashable {
    var editorVisible: Bool
    var terminalVisible: Bool

    static let both = PaneVisibility(editorVisible: true, terminalVisible: true)
    static let editorOnly = PaneVisibility(editorVisible: true, terminalVisible: false)
    static let terminalOnly = PaneVisibility(editorVisible: false, terminalVisible: true)
}

enum FileClassification: Sendable {
    case editable
    case readOnly
    case tooLarge
}

enum TabStatus: Sendable, Equatable {
    case loading
    case editable
    case readOnly
    case binary
    case tooLarge(size: Int64)
    case deleted
    case saving
    case savedFlash
    case failed(String)
}

enum DirectoryLoadState: Sendable, Equatable {
    case notLoaded
    case loading
    case loaded
    case failed(String)
}

/// Load state for the per-sandbox changed-files list. Distinguishes a
/// non-git-repository state (a placeholder, not a toast) from a transient
/// provider failure (which produces a toast and keeps the prior list).
enum ChangedFilesLoadState: Sendable, Equatable {
    case notLoaded
    case loading
    case loaded
    case notGitRepository
    case failed(String)
}

// MARK: - EditorTab

struct EditorTab: Sendable, Identifiable {
    let id: UUID
    let path: URL
    var status: TabStatus
    var contents: Data
    var savedFingerprint: Data
    var tentativelyDirty: Bool
    var scrollPosition: Int
    var cursorPosition: Int
    var pendingIndicator: Bool

    init(id: UUID = UUID(), path: URL, status: TabStatus, contents: Data, savedFingerprint: Data) {
        self.id = id
        self.path = path
        self.status = status
        self.contents = contents
        self.savedFingerprint = savedFingerprint
        self.tentativelyDirty = false
        self.scrollPosition = 0
        self.cursorPosition = 0
        self.pendingIndicator = false
    }
}

// MARK: - SandboxWorkspaceState

struct SandboxWorkspaceState: Sendable {
    let sandboxName: String
    var workspaceRoot: URL
    var tabs: [EditorTab]
    var activeTabID: UUID?
    var changedFiles: [ChangedFileEntry]
    var changedFilesLoadState: ChangedFilesLoadState
    var layoutRatio: Double
    var paneVisibility: PaneVisibility
    var statSnapshots: [URL: FileStat]
    var isWorkspaceMissing: Bool

    init(sandboxName: String, workspaceRoot: URL) {
        self.sandboxName = sandboxName
        self.workspaceRoot = workspaceRoot
        self.tabs = []
        self.activeTabID = nil
        self.changedFiles = []
        self.changedFilesLoadState = .notLoaded
        self.layoutRatio = 0.5
        self.paneVisibility = .both
        self.statSnapshots = [:]
        self.isWorkspaceMissing = false
    }
}

// MARK: - EditorStore

@MainActor @Observable final class EditorStore {
    // MARK: Constants
    static let softSizeCap: Int64 = 2 * 1024 * 1024
    static let hardSizeCap: Int64 = 20 * 1024 * 1024
    static let softLineCap: Int = 50_000
    static let maxOpenTabs: Int = 20
    static let debounceMillis: UInt64 = 500
    static let pendingIndicatorMillis: UInt64 = 250

    // MARK: Observable state
    var workspaces: [String: SandboxWorkspaceState] = [:]
    /// The close-confirmation dialog. When set the UI presents a modal.
    var pendingCloseConfirmation: PendingCloseConfirmation?
    /// The external-change dialog. When set the UI presents a modal.
    var pendingExternalChange: PendingExternalChange?
    /// Over-20-tab warning presentation flag.
    var showTabLimitWarning: Bool = false

    // MARK: Non-observed transient state
    @ObservationIgnored private var bufferPullCallbacks: [UUID: @MainActor () -> Data] = [:]
    @ObservationIgnored private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let provider: any EditorDocumentProvider
    @ObservationIgnored private let toastManager: ToastManager

    // MARK: - Init + shared accessor

    init(provider: any EditorDocumentProvider, toastManager: ToastManager) {
        self.provider = provider
        self.toastManager = toastManager
    }

    private static var _shared: EditorStore?
    static var shared: EditorStore {
        if let s = _shared { return s }
        fatalError("EditorStore.shared accessed before configuration. Call EditorStore.configureShared(_:) in sbx_uiApp.init().")
    }
    static func configureShared(_ store: EditorStore) { _shared = store }

    // MARK: - Pending dialog state types

    struct PendingCloseConfirmation: Identifiable {
        let id = UUID()
        let sandboxName: String
        let scope: Scope
        let dirty: [DirtyTabSummary]

        enum Scope { case tab(UUID); case sandbox; case all }
    }

    struct PendingExternalChange: Identifiable {
        let id = UUID()
        let sandboxName: String
        let tabID: UUID
        let path: URL
        let onDiskStat: FileStat
    }

    // MARK: - Lifecycle

    func open(sandbox: Sandbox) {
        let name = sandbox.name
        if workspaces[name] == nil {
            let root = URL(fileURLWithPath: sandbox.workspace)
            var state = SandboxWorkspaceState(sandboxName: name, workspaceRoot: root)
            state.isWorkspaceMissing = sandbox.workspace.isEmpty
            workspaces[name] = state
            appLog(.info, "Editor", "workspace opened \(name)", detail: sandbox.workspace)
            if !sandbox.workspace.isEmpty {
                Task { await self.refreshChangedFiles(sandboxName: name) }
            }
        } else if var state = workspaces[name] {
            // Re-entry: refresh workspace path in case sandbox moved.
            state.workspaceRoot = URL(fileURLWithPath: sandbox.workspace)
            state.isWorkspaceMissing = sandbox.workspace.isEmpty
            workspaces[name] = state
        }
    }

    /// Observes changes to the sandbox set. Buffers are preserved for stopped
    /// sandboxes; state is garbage-collected only when the sandbox is fully
    /// removed from `SandboxStore.sandboxes`.
    func syncSandboxStatus(sandboxes: [Sandbox]) {
        let knownNames = Set(sandboxes.map(\.name))
        for name in Array(workspaces.keys) where !knownNames.contains(name) {
            discardSandbox(name: name)
        }
    }

    private func discardSandbox(name: String) {
        if let state = workspaces[name] {
            for tab in state.tabs {
                bufferPullCallbacks.removeValue(forKey: tab.id)
                debounceTasks.removeValue(forKey: tab.id)?.cancel()
            }
        }
        workspaces.removeValue(forKey: name)
        appLog(.info, "Editor", "workspace discarded \(name)")
    }

    /// Drive from `ShellView.onBack` / `disconnect`. Returns whether the caller
    /// should proceed with teardown. If dirty tabs exist and `force` is false,
    /// sets `pendingCloseConfirmation` and returns `.needsConfirmation`.
    @discardableResult
    func closeSandbox(_ sandboxName: String, force: Bool) -> CloseResult {
        guard let state = workspaces[sandboxName] else { return .closed }
        let dirty = dirtyTabsSummary(for: sandboxName)
        if !dirty.isEmpty && !force {
            pendingCloseConfirmation = PendingCloseConfirmation(
                sandboxName: sandboxName, scope: .sandbox, dirty: dirty
            )
            return .needsConfirmation
        }
        for tab in state.tabs {
            bufferPullCallbacks.removeValue(forKey: tab.id)
            debounceTasks.removeValue(forKey: tab.id)?.cancel()
        }
        // Keep the workspace state (tab set empty? no — clear tabs on explicit
        // sandbox close so the UI re-mounts fresh on next entry).
        var newState = state
        newState.tabs = []
        newState.activeTabID = nil
        workspaces[sandboxName] = newState
        return .closed
    }

    // MARK: - Changed files (git status)

    /// Refreshes the changed-files list for `sandboxName` by asking the provider
    /// to run `git status`. Non-git repos update load state to `.notGitRepository`
    /// (the UI renders the `NotGitRepoPlaceholder`); git-unavailable and other
    /// provider errors surface a toast and keep the prior list.
    @discardableResult
    func refreshChangedFiles(sandboxName: String) async -> Bool {
        guard let state = workspaces[sandboxName] else { return false }
        let root = state.workspaceRoot
        if state.isWorkspaceMissing { return false }
        setChangedFilesLoadState(sandboxName: sandboxName, to: .loading)
        do {
            let entries = try await provider.listChangedFiles(in: root)
            setChangedFiles(sandboxName: sandboxName, entries: entries)
            setChangedFilesLoadState(sandboxName: sandboxName, to: .loaded)
            return true
        } catch {
            let nsErr = error as NSError
            if nsErr.domain == EditorErrorDomain,
               nsErr.code == EditorErrorCode.notGitRepository.rawValue {
                setChangedFiles(sandboxName: sandboxName, entries: [])
                setChangedFilesLoadState(sandboxName: sandboxName, to: .notGitRepository)
                appLog(.info, "Editor", "workspace is not a git repository \(root.path)")
                return false
            }
            setChangedFilesLoadState(sandboxName: sandboxName, to: .failed(nsErr.localizedDescription))
            toastManager.show("Editor: listChangedFiles failed — \(nsErr.localizedDescription) [\(nsErr.domain):\(nsErr.code)]")
            appLog(.error, "Editor", "listChangedFiles failed \(root.path)", detail: nsErr.localizedDescription)
            return false
        }
    }

    /// Returns the changed-file entry (if any) for an absolute path in the
    /// given sandbox. Used by `openFile` to honor deleted-file handling.
    private func changedFileEntry(sandboxName: String, path: URL) -> ChangedFileEntry? {
        guard let state = workspaces[sandboxName] else { return nil }
        let normalized = path.standardizedFileURL
        return state.changedFiles.first(where: { $0.url == normalized })
    }

    private func setChangedFiles(sandboxName: String, entries: [ChangedFileEntry]) {
        guard var state = workspaces[sandboxName] else { return }
        state.changedFiles = entries
        workspaces[sandboxName] = state
    }

    private func setChangedFilesLoadState(sandboxName: String, to value: ChangedFilesLoadState) {
        guard var state = workspaces[sandboxName] else { return }
        state.changedFilesLoadState = value
        workspaces[sandboxName] = state
    }

    // MARK: - File open

    func openFile(sandboxName: String, path: URL) async {
        guard let state = workspaces[sandboxName] else { return }
        let normalized: URL
        do {
            normalized = try EditorPath.validate(path, within: state.workspaceRoot)
        } catch {
            appLog(.warn, "Editor", "openFile out of scope \(path.path)")
            return
        }
        // Dedup: focus existing tab if present.
        if let existing = state.tabs.first(where: { $0.path == normalized }) {
            activateTab(sandboxName: sandboxName, tabID: existing.id)
            return
        }
        // 20-tab warning before opening another file.
        if state.tabs.count >= Self.maxOpenTabs {
            showTabLimitWarning = true
            return
        }
        // Deleted-file placeholder: the changed-files list reports this path
        // as deleted, so skip stat+readFile entirely.
        if let entry = changedFileEntry(sandboxName: sandboxName, path: normalized),
           entry.changeType == .deleted {
            let placeholderID = UUID()
            var tab = EditorTab(
                id: placeholderID,
                path: normalized,
                status: .deleted,
                contents: Data(),
                savedFingerprint: Data()
            )
            tab.pendingIndicator = false
            appendTab(sandboxName: sandboxName, tab: tab, activate: true)
            appLog(.info, "Editor", "openFile deleted \(normalized.path)")
            return
        }
        // Insert placeholder "loading" tab so UI transitions within 150 ms.
        let placeholderID = UUID()
        let placeholder = EditorTab(
            id: placeholderID,
            path: normalized,
            status: .loading,
            contents: Data(),
            savedFingerprint: Data()
        )
        appendTab(sandboxName: sandboxName, tab: placeholder, activate: true)

        // Schedule pending-indicator after 250 ms.
        let pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.pendingIndicatorMillis * 1_000_000)
            if Task.isCancelled { return }
            await MainActor.run { self?.setPendingIndicator(sandboxName: sandboxName, tabID: placeholderID, value: true) }
        }

        defer { pendingTask.cancel() }

        // Stat first to classify size.
        do {
            let s = try await provider.stat(at: normalized)
            if s.size > Self.hardSizeCap {
                updateTab(sandboxName: sandboxName, tabID: placeholderID) { tab in
                    tab.status = .tooLarge(size: s.size)
                    tab.pendingIndicator = false
                }
                updateStatSnapshot(sandboxName: sandboxName, path: normalized, stat: s)
                return
            }
            let classification: FileClassification = s.size > Self.softSizeCap ? .readOnly : .editable
            let data = try await provider.readFile(at: normalized)
            updateStatSnapshot(sandboxName: sandboxName, path: normalized, stat: s)
            // Check UTF-8 decode.
            if String(data: data, encoding: .utf8) == nil {
                updateTab(sandboxName: sandboxName, tabID: placeholderID) { tab in
                    tab.contents = data
                    tab.status = .binary
                    tab.pendingIndicator = false
                }
                return
            }
            // Line-count check for soft cap.
            var finalClassification = classification
            if finalClassification == .editable {
                let lineCount = data.reduce(into: 0) { acc, b in if b == 0x0A { acc += 1 } }
                if lineCount > Self.softLineCap { finalClassification = .readOnly }
            }
            let fingerprint = Self.fingerprint(of: data)
            updateTab(sandboxName: sandboxName, tabID: placeholderID) { tab in
                tab.contents = data
                tab.savedFingerprint = fingerprint
                tab.status = finalClassification == .readOnly ? .readOnly : .editable
                tab.pendingIndicator = false
            }
        } catch {
            let nsErr = error as NSError
            updateTab(sandboxName: sandboxName, tabID: placeholderID) { tab in
                tab.status = .failed(nsErr.localizedDescription)
                tab.pendingIndicator = false
            }
            toastManager.show("Editor: open failed — \(nsErr.localizedDescription) [\(nsErr.domain):\(nsErr.code)]")
            appLog(.error, "Editor", "openFile failed \(normalized.path)", detail: nsErr.localizedDescription)
        }
    }

    // MARK: - Tab lifecycle

    func activateTab(sandboxName: String, tabID: UUID) {
        guard var state = workspaces[sandboxName] else { return }
        state.activeTabID = tabID
        workspaces[sandboxName] = state
    }

    /// Activate the N-th open tab (1-indexed), matching Cmd+N shortcut. Does
    /// nothing if `index` is out of range.
    func activateTab(sandboxName: String, index: Int) {
        guard let state = workspaces[sandboxName] else { return }
        guard index >= 1 && index <= state.tabs.count else { return }
        activateTab(sandboxName: sandboxName, tabID: state.tabs[index - 1].id)
    }

    @discardableResult
    func closeTab(sandboxName: String, tabID: UUID, force: Bool) -> CloseResult {
        guard let state = workspaces[sandboxName] else { return .closed }
        guard let tab = state.tabs.first(where: { $0.id == tabID }) else { return .closed }
        if isTabDirty(sandboxName: sandboxName, tabID: tabID, reconcile: true) && !force {
            let summary = [DirtyTabSummary(tabID: tab.id, sandboxName: sandboxName, path: tab.path)]
            pendingCloseConfirmation = PendingCloseConfirmation(
                sandboxName: sandboxName, scope: .tab(tabID), dirty: summary
            )
            return .needsConfirmation
        }
        removeTabForcefully(sandboxName: sandboxName, tabID: tabID)
        return .closed
    }

    private func removeTabForcefully(sandboxName: String, tabID: UUID) {
        guard var state = workspaces[sandboxName] else { return }
        state.tabs.removeAll { $0.id == tabID }
        if state.activeTabID == tabID {
            state.activeTabID = state.tabs.last?.id
        }
        workspaces[sandboxName] = state
        bufferPullCallbacks.removeValue(forKey: tabID)
        debounceTasks.removeValue(forKey: tabID)?.cancel()
    }

    private func appendTab(sandboxName: String, tab: EditorTab, activate: Bool) {
        guard var state = workspaces[sandboxName] else { return }
        state.tabs.append(tab)
        if activate { state.activeTabID = tab.id }
        workspaces[sandboxName] = state
    }

    private func updateTab(sandboxName: String, tabID: UUID, _ mutate: (inout EditorTab) -> Void) {
        guard var state = workspaces[sandboxName] else { return }
        guard let index = state.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        var tab = state.tabs[index]
        mutate(&tab)
        state.tabs[index] = tab
        workspaces[sandboxName] = state
    }

    private func setPendingIndicator(sandboxName: String, tabID: UUID, value: Bool) {
        updateTab(sandboxName: sandboxName, tabID: tabID) { $0.pendingIndicator = value }
    }

    private func updateStatSnapshot(sandboxName: String, path: URL, stat: FileStat) {
        guard var state = workspaces[sandboxName] else { return }
        state.statSnapshots[path.standardizedFileURL] = stat
        workspaces[sandboxName] = state
    }

    // MARK: - Dirty pipeline

    func registerBufferPull(sandboxName: String, tabID: UUID, pull: @escaping @MainActor () -> Data) {
        bufferPullCallbacks[tabID] = pull
    }

    func unregisterBufferPull(tabID: UUID) {
        bufferPullCallbacks.removeValue(forKey: tabID)
    }

    func onBufferMutated(sandboxName: String, tabID: UUID) {
        // O(1): mark tentativelyDirty, (re)schedule a 500 ms idle debounce.
        updateTab(sandboxName: sandboxName, tabID: tabID) { $0.tentativelyDirty = true }
        debounceTasks.removeValue(forKey: tabID)?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceMillis * 1_000_000)
            if Task.isCancelled { return }
            await self?.fingerprintReconcile(sandboxName: sandboxName, tabID: tabID)
        }
        debounceTasks[tabID] = task
    }

    private func fingerprintReconcile(sandboxName: String, tabID: UUID) {
        guard let pull = bufferPullCallbacks[tabID] else { return }
        let data = pull()
        let fp = Self.fingerprint(of: data)
        updateTab(sandboxName: sandboxName, tabID: tabID) { tab in
            tab.contents = data
            if fp == tab.savedFingerprint {
                tab.tentativelyDirty = false
            }
        }
    }

    /// Pulls the current buffer synchronously (through the registered
    /// callback) and returns whether the tab's effective dirty predicate is
    /// true. Used by dirtyTabsSummary and save.
    private func isTabDirty(sandboxName: String, tabID: UUID, reconcile: Bool) -> Bool {
        guard let state = workspaces[sandboxName],
              let tab = state.tabs.first(where: { $0.id == tabID }) else { return false }
        if !reconcile {
            return tab.tentativelyDirty || Self.fingerprint(of: tab.contents) != tab.savedFingerprint
        }
        if let pull = bufferPullCallbacks[tabID] {
            let data = pull()
            let fp = Self.fingerprint(of: data)
            let dirty = fp != tab.savedFingerprint
            updateTab(sandboxName: sandboxName, tabID: tabID) { t in
                t.contents = data
                t.tentativelyDirty = dirty ? t.tentativelyDirty : false
            }
            return dirty
        }
        return tab.tentativelyDirty
    }

    // MARK: - Save

    @discardableResult
    func save(sandboxName: String, tabID: UUID) async -> SaveResult {
        guard let state = workspaces[sandboxName],
              let tab = state.tabs.first(where: { $0.id == tabID }) else { return .noChange }
        // Cancel any pending debounce — we're reconciling synchronously.
        debounceTasks.removeValue(forKey: tabID)?.cancel()
        let currentData: Data
        if let pull = bufferPullCallbacks[tabID] {
            currentData = pull()
        } else {
            currentData = tab.contents
        }
        let fp = Self.fingerprint(of: currentData)
        if fp == tab.savedFingerprint && !tab.tentativelyDirty {
            return .noChange
        }
        let path = tab.path
        // External-change probe.
        do {
            let onDisk = try await provider.stat(at: path)
            if let prior = state.statSnapshots[path.standardizedFileURL] {
                if prior.mtime != onDisk.mtime || prior.size != onDisk.size {
                    pendingExternalChange = PendingExternalChange(
                        sandboxName: sandboxName, tabID: tabID, path: path, onDiskStat: onDisk
                    )
                    return .externalChange(onDisk)
                }
            }
        } catch {
            // If stat fails, continue to write (the write will surface its own error).
        }
        updateTab(sandboxName: sandboxName, tabID: tabID) { $0.status = .saving }
        do {
            try await provider.writeFile(at: path, contents: currentData)
            let newStat = try? await provider.stat(at: path)
            updateTab(sandboxName: sandboxName, tabID: tabID) { t in
                t.contents = currentData
                t.savedFingerprint = fp
                t.tentativelyDirty = false
                t.status = .savedFlash
            }
            if let s = newStat {
                updateStatSnapshot(sandboxName: sandboxName, path: path, stat: s)
            }
            // Flash then return to editable.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.updateTab(sandboxName: sandboxName, tabID: tabID) { t in
                        if case .savedFlash = t.status { t.status = .editable }
                    }
                }
            }
            return .saved
        } catch {
            let nsErr = error as NSError
            updateTab(sandboxName: sandboxName, tabID: tabID) { t in
                t.status = .editable
                t.tentativelyDirty = true
            }
            toastManager.show("Editor: save failed — \(nsErr.localizedDescription) [\(nsErr.domain):\(nsErr.code)]")
            appLog(.error, "Editor", "save failed \(path.path)", detail: nsErr.localizedDescription)
            return .failed(nsErr)
        }
    }

    @discardableResult
    func saveAll(sandboxName: String) async -> [UUID: SaveResult] {
        var results: [UUID: SaveResult] = [:]
        guard let state = workspaces[sandboxName] else { return results }
        for tab in state.tabs {
            if isTabDirty(sandboxName: sandboxName, tabID: tab.id, reconcile: true) {
                results[tab.id] = await save(sandboxName: sandboxName, tabID: tab.id)
            }
        }
        return results
    }

    // MARK: - External change handling

    @discardableResult
    func resolveExternalChange(reload: Bool) async -> ExternalChangeResult {
        guard let pending = pendingExternalChange else { return .unchanged }
        defer { pendingExternalChange = nil }
        if reload {
            do {
                let data = try await provider.readFile(at: pending.path)
                let stat = try await provider.stat(at: pending.path)
                let fp = Self.fingerprint(of: data)
                updateTab(sandboxName: pending.sandboxName, tabID: pending.tabID) { t in
                    t.contents = data
                    t.savedFingerprint = fp
                    t.tentativelyDirty = false
                    t.status = .editable
                }
                updateStatSnapshot(sandboxName: pending.sandboxName, path: pending.path, stat: stat)
                return .reloaded
            } catch {
                let nsErr = error as NSError
                toastManager.show("Editor: reload failed — \(nsErr.localizedDescription) [\(nsErr.domain):\(nsErr.code)]")
                return .conflict(stat: pending.onDiskStat)
            }
        } else {
            // Keep mine: mark snapshot stale so subsequent save overwrites.
            updateStatSnapshot(sandboxName: pending.sandboxName, path: pending.path, stat: pending.onDiskStat)
            return .conflict(stat: pending.onDiskStat)
        }
    }

    /// Show-Diff stub per 10.4: surface a toast for MVP.
    func acknowledgeShowDiffStub() {
        toastManager.show("Diff viewer coming soon.", isError: false)
        pendingExternalChange = nil
    }

    // MARK: - Dirty summary

    /// Returns every tab with unsaved edits (across all sandboxes).
    /// Tabs flagged `tentativelyDirty` are synchronously reconciled here so
    /// the summary reflects ground truth even if the 500 ms idle debounce
    /// has not yet fired — protects fast-quit and close-with-dirty.
    func dirtyTabsSummary() -> [DirtyTabSummary] {
        var summaries: [DirtyTabSummary] = []
        for (name, _) in workspaces {
            summaries.append(contentsOf: dirtyTabsSummary(for: name))
        }
        return summaries
    }

    func dirtyTabsSummary(for sandboxName: String) -> [DirtyTabSummary] {
        guard let state = workspaces[sandboxName] else { return [] }
        var out: [DirtyTabSummary] = []
        for tab in state.tabs {
            if isTabDirty(sandboxName: sandboxName, tabID: tab.id, reconcile: true) {
                out.append(DirtyTabSummary(tabID: tab.id, sandboxName: sandboxName, path: tab.path))
            }
        }
        return out
    }

    // MARK: - Layout + pane visibility

    func setLayoutRatio(_ ratio: Double, for sandboxName: String) {
        guard var state = workspaces[sandboxName] else { return }
        state.layoutRatio = max(0.1, min(0.9, ratio))
        workspaces[sandboxName] = state
    }

    func setPaneVisibility(_ vis: PaneVisibility, for sandboxName: String) {
        guard var state = workspaces[sandboxName] else { return }
        var effective = vis
        if !effective.editorVisible && !effective.terminalVisible {
            effective = .terminalOnly // guarantee at least one visible
        }
        state.paneVisibility = effective
        workspaces[sandboxName] = state
    }

    func paneVisibility(for sandboxName: String) -> PaneVisibility {
        workspaces[sandboxName]?.paneVisibility ?? .both
    }

    // MARK: - Confirm-close dialog resolution

    enum ConfirmCloseChoice { case save, discard, cancel }

    @discardableResult
    func resolvePendingClose(_ choice: ConfirmCloseChoice) async -> CloseResult {
        guard let pending = pendingCloseConfirmation else { return .closed }
        defer { pendingCloseConfirmation = nil }
        switch choice {
        case .cancel:
            return .cancelled
        case .discard:
            switch pending.scope {
            case .tab(let tabID):
                removeTabForcefully(sandboxName: pending.sandboxName, tabID: tabID)
                return .closed
            case .sandbox:
                return closeSandbox(pending.sandboxName, force: true)
            case .all:
                for name in Array(workspaces.keys) { _ = closeSandbox(name, force: true) }
                return .closed
            }
        case .save:
            switch pending.scope {
            case .tab(let tabID):
                let result = await save(sandboxName: pending.sandboxName, tabID: tabID)
                if case .saved = result {
                    removeTabForcefully(sandboxName: pending.sandboxName, tabID: tabID)
                    return .closed
                }
                return .saveFailed([tabID])
            case .sandbox:
                let results = await saveAll(sandboxName: pending.sandboxName)
                let failures = results.filter {
                    if case .failed = $0.value { return true }
                    return false
                }.map(\.key)
                if failures.isEmpty {
                    return closeSandbox(pending.sandboxName, force: true)
                }
                return .saveFailed(failures)
            case .all:
                var failed: [UUID] = []
                for name in Array(workspaces.keys) {
                    let results = await saveAll(sandboxName: name)
                    failed.append(contentsOf: results.filter {
                        if case .failed = $0.value { return true }
                        return false
                    }.map(\.key))
                }
                if failed.isEmpty {
                    for name in Array(workspaces.keys) { _ = closeSandbox(name, force: true) }
                    return .closed
                }
                return .saveFailed(failed)
            }
        }
    }

    // MARK: - Classification helper

    static func classifyFile(size: Int64) -> FileClassification {
        if size > hardSizeCap { return .tooLarge }
        if size > softSizeCap { return .readOnly }
        return .editable
    }

    // MARK: - Fingerprint helper

    static func fingerprint(of data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - External change manual check

    func checkExternalChange(sandboxName: String, tabID: UUID) async -> ExternalChangeResult {
        guard let state = workspaces[sandboxName],
              let tab = state.tabs.first(where: { $0.id == tabID }) else { return .unchanged }
        do {
            let s = try await provider.stat(at: tab.path)
            if let prior = state.statSnapshots[tab.path.standardizedFileURL],
               (prior.mtime != s.mtime || prior.size != s.size) {
                return .conflict(stat: s)
            }
            return .unchanged
        } catch {
            return .unchanged
        }
    }
}
