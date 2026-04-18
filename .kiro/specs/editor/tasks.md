# Implementation Plan

Tasks are ordered for incremental delivery: foundational data layer first, then store, then views, then integration, then tests. `(P)` marks tasks that can run in parallel after their predecessors land; all such tasks modify disjoint files and have no shared mutable state.

- [ ] 1. Foundation — domain types, provider protocol, and path scope

- [x] 1.1 Define EditorDocumentProvider protocol and domain value types
  - Add a Sendable protocol for sandbox-interior file I/O with listDirectory, listChangedFiles, readFile, writeFile, and stat methods; errors are raised as NSError for uniform toast surfacing.
  - Define FileEntry (basename, absolute URL, isDirectory, size, mtime) and FileStat (size, mtime, isDirectory) as Sendable value types.
  - Define ChangedFileEntry (absolute URL, relative path, change type) as a Sendable Identifiable value type, and GitChangeType as a Sendable enum with cases modified, added, deleted, renamed, and untracked.
  - Define an EditorError enum with pathOutsideWorkspace, fileTooLarge, binaryFile, workspaceMissing, notGitRepository, and gitUnavailable cases.
  - Place the protocol and types in the macOS-only editor services directory (not SBXCore) since the Linux CLI does not need the editor.
  - _Requirements: 2.2, 2.3, 13.1, 13.3_

- [x] 1.2 (P) Implement the default FileManager-backed provider with git status
  - Provide a stateless Sendable struct that implements file I/O methods using FileManager.contentsOfDirectory, Data(contentsOf:), Data.write(to:options: [.atomic]), and FileManager.attributesOfItem.
  - Implement listChangedFiles by spawning a Process with git status --porcelain=v1, currentDirectoryURL set to the workspace root; parse each output line's two-character status prefix into the corresponding GitChangeType and the remainder into a relative path; sort results alphabetically by relative path.
  - Handle git-not-found (Process launch throws) by throwing an NSError with the gitUnavailable error, and non-git-repo (exit code 128) by throwing notGitRepository.
  - Guarantee byte-exact round-trips with no trailing newline insertion, no line-ending rewriting, and no encoding transforms.
  - Emit an info-level log event to the shared log store on every successful operation (including listChangedFiles with entry count), and an error-level event on failure.
  - _Requirements: 2.2, 2.3, 2.10, 3.1, 5.1, 5.7, 13.3, 13.6_

- [x] 1.3 (P) Implement EditorPath scope validator
  - Provide a helper that standardizes a candidate URL, checks that the resolved path stays inside or equals the workspace root, and rejects parent-traversal and out-of-scope absolute paths by throwing EditorError.pathOutsideWorkspace.
  - Do not follow symlinks; a symlink whose standardized path falls outside the workspace is rejected.
  - Mirror the existing validatePathScope pattern used in the plugin API handler.
  - _Requirements: 3.7_

- [x] 1.4 (P) Implement the in-memory fake provider for unit tests
  - Provide an actor-backed fixture that stores files in a per-instance dictionary keyed by absolute path, returning deterministic advancing mtime values so external-change tests can manipulate them explicitly.
  - Store a seeded changedFiles array for listChangedFiles and expose a failListChanged flag to simulate git-not-found or non-git-repo errors.
  - Expose helpers for seeding fixture files and changed-file entries, and for rigging read, write, stat, listDirectory, or listChangedFiles to throw specific NSError values.
  - _Requirements: 14.4_

- [x] 1.5 Unit tests for the provider layer
  - Exercise round-trip byte-exactness (files with and without trailing newlines, files containing EOF-looking sentinels) against the default provider in a per-test temp directory.
  - Exercise listChangedFiles against a per-test temp directory with git init, git add, and a modified file; assert entries include the expected change types and are sorted alphabetically.
  - Exercise listChangedFiles against a non-git directory and assert it throws notGitRepository.
  - Exercise EditorPath scope validation against absolute, parent-traversal, and in-workspace paths.
  - Exercise the fake provider for contract parity with the default implementation (same inputs → same observable results), including listChangedFiles with seeded entries and failListChanged rigging.
  - _Requirements: 2.2, 2.9, 2.10, 3.7, 5.7, 14.4_

- [ ] 2. EditorStore skeleton — lifecycle, state, and shared accessor

- [x] 2.1 Define the editor store with per-sandbox state
  - Declare an @Observable @MainActor final class that owns a dictionary of per-sandbox workspace state keyed by sandbox name; each state holds a changed-files list with load state, open tabs in order, the active tab, layout ratio, pane visibility, per-path stat snapshots, per-tab saved fingerprint, and per-tab tentativelyDirty flag.
  - Implement open (which calls refreshChangedFiles on mount), closeSandbox, and syncSandboxStatus; preserve workspace state for sandboxes that transition to stopped so the user can resume editing on re-entry, and garbage-collect only when a sandbox is fully removed from the sandbox store.
  - Implement refreshChangedFiles that calls the provider's listChangedFiles and updates the changed-files list and load state; surface errors via ToastManager and show the not-a-git-repo placeholder for non-git workspaces.
  - Inject the provider and toast manager at construction; do not hold references to other @Observable stores.
  - _Requirements: 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 4.6, 6.6, 10.2, 10.3, 13.2_

- [x] 2.2 Expose a shared accessor for the app lifecycle hook
  - Add a lazy static shared accessor to the editor store that returns the instance configured at app init, mirroring the existing LogStore.shared pattern.
  - The adapter reads this accessor lazily at termination time; the store does not retain any reference to the adapter.
  - _Requirements: 10.7_

- [ ] 3. File opening

- [x] 3.1 Implement file-open with size classification, deleted-file handling, and binary fallback
  - Validate every candidate path through EditorPath before any I/O; reject out-of-scope paths silently with a log event.
  - When the changed file has changeType deleted, open a deleted-file placeholder tab without invoking readFile.
  - Stat before reading; if size exceeds the hard cap, show a file-too-large placeholder without invoking readFile; if size exceeds the soft cap, read and open in read-only preview mode with a banner.
  - Decode as UTF-8; on decode failure, refuse editing and display a binary notice with a copy-path action.
  - De-duplicate re-opens of the same path to focus the existing tab.
  - Render a skeleton placeholder while the read is in flight and disable keyboard input for that tab until the read completes; complete the tab UI transition within 150 ms on a local filesystem while the read itself finishes asynchronously; show a pending indicator if any operation runs longer than 250 ms.
  - _Requirements: 2.4, 2.5, 3.1, 3.2, 3.4, 3.5, 3.6, 3.7, 11.1, 11.2, 11.3, 11.4_

- [ ] 4. Tab management, dirty pipeline, save, and summary

- [x] 4.1 Implement multi-tab management
  - Maintain a per-sandbox ordered tab list with an active tab, per-tab scroll position, and per-tab cursor location; switching tabs restores both.
  - Close a tab subject to the unsaved guard; force-close discards edits; support Cmd+1 through Cmd+9 to activate tabs, and an overflow dropdown when the tab bar overflows.
  - Warn the user before opening a new file when the open-tab count already equals 20.
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 11.5_

- [x] 4.2 Implement the pull-based debounced dirty pipeline
  - Accept an onBufferMutated signal from the editor buffer view (no payload) and mark the tab tentativelyDirty in O(1) time; cancel and reschedule a 500 ms idle debounce on each mutation.
  - On debounce fire, invoke the registered buffer-pull callback to read the current buffer, compute a CryptoKit SHA-256 digest, compare against the saved fingerprint, and clear tentativelyDirty when they match.
  - Accept registerBufferPull and clear the registration on tab close or external-change reload; cancel any pending debounce on tab close to avoid firing against a torn-down widget.
  - _Requirements: 4.1, 4.2, 4.3, 4.5, 11.7_

- [x] 4.3 Implement save, save-all, external-change detection, and error surfacing
  - On Cmd+S, synchronously pull the current buffer, fingerprint it, and compare against the saved fingerprint to decide whether a write is actually needed (this flushes the debounce window on the save path).
  - Before writing, stat the path; if the mtime or size has changed against the snapshot, present the external-change dialog with Reload, Keep Mine, and Show Diff options (the diff action may be a toast stub for MVP).
  - Perform an atomic write through the provider; on success, update the saved fingerprint and the stat snapshot and flash the tab briefly in secondary color.
  - On failure, keep the tab dirty, re-enable buffer input, and surface an error toast containing the NSError localizedDescription plus domain and code.
  - Implement save-all by iterating dirty tabs sequentially and reporting per-tab results.
  - Do not auto-refresh the changed-files list on save; the list updates only on explicit refresh or re-mount.
  - _Requirements: 2.11, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 9.4, 10.4, 10.5, 10.6_

- [x] 4.4 Implement dirtyTabsSummary with synchronous reconciliation
  - Return every tab that is either flagged tentativelyDirty or whose fingerprint differs from the saved fingerprint.
  - For tabs in tentativelyDirty state, synchronously pull the buffer and compute a fresh fingerprint before returning so the summary reflects ground truth even when the idle debounce has not yet fired.
  - Expose the summary for the close-with-dirty dialog, save-all confirmation, and the quit prompt.
  - _Requirements: 10.1, 10.7_

- [x] 5. EditorStore unit tests
  - Cover refreshChangedFiles populating the list from the provider, non-git-repo error handling, and git-unavailable error handling.
  - Cover openFile classifications (editable, read-only, too-large, binary, deleted-file placeholder, out-of-scope); tab lifecycle (open, activate, close, force-close, 20-tab warning); the dirty pipeline signal → debounce → reconcile → revert-to-clean; save success and failure; external-change detection with a stat mismatch; sandbox-stop state preservation and re-entry restoration; dirtyTabsSummary synchronous reconciliation within the debounce window; and closeTab cancelling pending debounces.
  - Cover change-type badge correctness by seeding files with each GitChangeType and verifying badge text matches.
  - _Requirements: 14.1_

- [ ] 6. App integration and mock-workspace wiring

- [x] 6.1 Wire the editor store into the app shell
  - Construct the editor store in the app init with a shared provider instance and the shared toast manager; inject via the SwiftUI environment.
  - Install the same instance into EditorStore.shared so the app-delegate adapter can reach it.
  - _Requirements: 13.2_

- [x] 6.2 Add the app-delegate adapter for the quit-with-dirty prompt
  - Attach an NSApplicationDelegate via NSApplicationDelegateAdaptor; implement applicationShouldTerminate to read EditorStore.shared.dirtyTabsSummary and, when non-empty, present an NSAlert with Save All, Discard, and Cancel; proceed via terminateNow, terminateLater with save-all, or terminateCancel accordingly.
  - _Requirements: 10.7_

- [x] 6.3 Make the mock workspace path test-configurable
  - Update the sandbox-creation sheet so that, under CLI-mock mode, the workspace path honors an SBX_CLI_MOCK_WORKSPACE environment variable while preserving the existing default when the variable is unset.
  - _Requirements: 14.3_

- [ ] 7. Editor UI components

- [x] 7.1 Select and integrate the text-editing widget
  - Verify the minimum macOS deployment target of CodeEditorView (mchakravarty, Apache-2.0) is compatible with the project's macOS 14 floor; if compatible, add the package to the Swift Package graph; otherwise commit to a wrapped NSTextView as the fallback, isolated to the buffer view.
  - Wire up the phase-2 syntax-highlighting feature flag so disabled builds render plain monospaced text on the dark surface and enabled builds apply the chosen grammar asynchronously without blocking input; large files bypass highlighting regardless of the flag.
  - _Requirements: 3.3, 7.1, 7.2, 7.3, 7.4, 7.5, 11.6_

- [x] 7.2 Build the editor buffer view
  - Wrap the chosen widget to render UTF-8 text on the dark surface with a line-number gutter.
  - Register a buffer-pull callback on appear and clear it on disappear or tab close; emit onBufferMutated on every text change; disable keyboard input while the store reports the tab is loading.
  - Support standard macOS text-editing shortcuts (Cmd+Z/Shift+Z, Cmd+X/C/V, Cmd+A, arrow navigation, option-arrow word jump) and trigger save through the store on Cmd+S.
  - _Requirements: 3.2, 3.3, 4.1, 4.4, 4.5, 11.6_

- [x] 7.3 (P) Build the changed-files list view
  - Render a flat list of git-changed files sorted alphabetically by relative path, with a change-type badge (M/A/D/R/U) next to each row using tonal colors from the design system.
  - Show an inline spinner in the panel header while the changed-files enumeration is in flight and disable file-open actions during loading.
  - Provide a refresh button in the panel header that triggers refreshChangedFiles on the store; clicking a file row calls openFile on the store (or focuses the existing tab).
  - Attach accessibility identifiers using the changedFileRow-{relativePath}, changedFileBadge-{relativePath}, and changedFileRefresh scheme so XCUITests can target individual elements.
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

- [x] 7.4 (P) Build the editor tabs view
  - Render a horizontal tab bar showing one tab per open file in open-time order; show the dirty glyph and accent-colored title when the tab is dirty; flash the tab briefly in secondary color on save success.
  - Provide an overflow dropdown listing all open tabs alphabetically with dirty markers when the tab bar overflows; bind Cmd+1 through Cmd+9 to activate the corresponding tab.
  - Attach accessibility identifiers using the relative path scheme.
  - _Requirements: 4.2, 5.3, 6.1, 6.4, 6.5_

- [x] 7.5 (P) Build the find-within-file bar
  - Reveal a find bar with input focus on Cmd+F; highlight all matches in the current buffer and display a current/total counter.
  - Navigate next on Return or Cmd+G (wrapping to start); previous on Shift+Return or Cmd+Shift+G.
  - Provide case-sensitive and whole-word toggles (both default off); dismiss with Escape, clearing highlights and returning focus to the buffer; re-run the query against the new buffer when the active tab changes.
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

- [x] 7.6 (P) Build placeholders, banners, and confirmation dialogs
  - Implement a sandbox-status / large-file / binary banner component for inline messaging within the editor pane.
  - Implement an empty-workspace placeholder shown when the active sandbox has no workspace path, a not-a-git-repo placeholder shown when the workspace has no .git directory, and a deleted-file placeholder shown when opening a file with changeType deleted.
  - Implement the unsaved-close confirmation dialog (Save / Discard / Cancel) and the external-change dialog (Reload / Keep Mine / Show Diff, the last shown as a toast stub in MVP).
  - _Requirements: 2.5, 2.8, 2.9, 3.4, 3.5, 10.1, 10.4_

- [ ] 8. Split-pane container and shell integration

- [x] 8.1 Build the sandbox workspace split view
  - Compose an HSplitView-based two-pane layout with a draggable splitter; observe the measured ratio through GeometryReader and commit it to the editor store on drag-end only to avoid feedback loops.
  - Provide collapse controls for each pane that toggle pane visibility in the store; guarantee at least one pane remains visible at a time.
  - Route the single nav bar's Dashboard and Disconnect actions through the store's close-sandbox flow so both pick up the unsaved-close dialog when dirty tabs exist; keep the terminal view wrapped with its existing session-scoped identity so session switching behaves unchanged.
  - Leave the existing session panel available as a fallback single-pane mount when the editor pane is collapsed.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 9.1, 9.2, 9.5, 13.4_

- [x] 8.2 Compose the editor pane layout
  - Arrange the changed-files list, tab bar, buffer view, find bar, and banners into the editor pane, substituting the empty-workspace or not-a-git-repo placeholder when appropriate.
  - Emit structured log events for every file operation so activity surfaces in the existing debug log overlay.
  - _Requirements: 2.1, 2.8, 2.9, 3.3, 10.2, 13.6_

- [x] 8.3 Integrate the workspace view into the app shell
  - In the shell view, replace the direct mount of the session panel for running sandboxes with the new workspace view; keep the running-sandbox gate intact so the editor never mounts for non-running selections.
  - Fan the shell's existing onChange observation over running-sandbox names into the editor store's syncSandboxStatus call alongside the existing session and kanban calls.
  - _Requirements: 1.1, 1.5, 4.6, 6.6, 9.3, 10.2, 10.3_

- [x] 9. Apply design-system tokens across editor views
  - Use surfaceLowest for the buffer background, surfaceContainer for the changed-files panel and tab bar, and surfaceContainerHigh for hovered rows.
  - Use accent for focus rings, the active-tab underline, and the dirty-state tab title; use secondary for the save-success flash; use error only for destructive affordances.
  - Use code font at 13 pt for buffer text, ui font at 12 pt for tab labels and changed-file rows, and code font at 11 pt for gutter line numbers; use the 8 pt corner radius for the find bar and floating dropdowns; avoid 1 px borders in favor of tonal surface shifts; render only dark-scheme assets.
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_

- [x] 10. End-to-end test coverage

- [x] 10.1 Build the editor UI-test base class
  - Provide an XCTestCase base class that, in setUpWithError, creates a per-test temp directory, seeds deterministic fixture files (README.md, a small source file), runs git init and git add via Process to create a valid git repository, sets SBX_CLI_MOCK_WORKSPACE to that directory, and in tearDownWithError removes the directory.
  - _Requirements: 14.3, 14.6_

- [x] 10.2 (P) XCUITest coverage for editor flows
  - Open a file from the changed-files list and assert the buffer renders the seeded contents.
  - Type into the buffer, press Cmd+S, and assert the dirty indicator disappears and the toast queue is empty.
  - Switch between two tabs and assert cursor position and scroll are restored.
  - Edit without saving, press Cmd+W, and assert the unsaved-close confirmation dialog appears.
  - Edit without saving, mutate the on-disk file, attempt to save, and assert the external-change dialog appears.
  - With an empty workspace path, assert the empty-workspace placeholder is visible and the save button is absent.
  - With a non-git workspace, assert the not-a-git-repo placeholder is visible.
  - Verify that the refresh button updates the changed-files list after modifying a file in the temp workspace.
  - Verify that change-type badges display the correct labels for modified and added files.
  - _Requirements: 14.2_

- [ ] 10.3 (P) XCUITest coverage for sandbox-stop preservation
  - Open a file, edit it, stop the sandbox from the dashboard, confirm the dashboard becomes the current view with no crash, restart the sandbox, re-enter the session, and assert the prior tab set, active tab, and dirty state are restored.
  - _Requirements: 14.5_

- [x] 11. Reserve the editor plugin API namespace for a future spec
  - Add editor.readState and editor.mutateState cases to the plugin permission enum without wiring any JSON-RPC handlers; document the cases as reserved for a future editor plugin spec, distinct from the existing file.read and file.write permissions.
  - _Requirements: 13.5_
