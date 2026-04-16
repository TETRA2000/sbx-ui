# Implementation Plan

Tasks are ordered for incremental delivery: foundational data layer first, then store, then views, then integration, then tests. `(P)` marks tasks that can run in parallel after their predecessors land; all such tasks modify disjoint files and have no shared mutable state.

- [ ] 1. Foundation — domain types, provider protocol, and path scope

- [ ] 1.1 Define EditorDocumentProvider protocol and domain value types
  - Add a Sendable protocol for sandbox-interior file I/O with listDirectory, readFile, writeFile, and stat methods; errors are raised as NSError for uniform toast surfacing.
  - Define FileEntry (basename, absolute URL, isDirectory, size, mtime) and FileStat (size, mtime, isDirectory) as Sendable value types.
  - Define an EditorError enum with pathOutsideWorkspace, fileTooLarge, binaryFile, and workspaceMissing cases.
  - Place the protocol and types in SBXCore so they are reachable from both macOS and any future Linux CLI surface.
  - _Requirements: 13.1, 13.3_

- [ ] 1.2 (P) Implement the default FileManager-backed provider
  - Provide a stateless Sendable struct that implements the protocol using FileManager.contentsOfDirectory, Data(contentsOf:), Data.write(to:options: [.atomic]), and FileManager.attributesOfItem.
  - Guarantee byte-exact round-trips with no trailing newline insertion, no line-ending rewriting, and no encoding transforms.
  - Emit an info-level log event to the shared log store on every successful operation, and an error-level event on failure, including the operation name, absolute path, and size or entry count.
  - _Requirements: 2.2, 3.1, 5.1, 5.7, 13.3, 13.6_

- [ ] 1.3 (P) Implement EditorPath scope validator
  - Provide a helper that standardizes a candidate URL, checks that the resolved path stays inside or equals the workspace root, and rejects parent-traversal and out-of-scope absolute paths by throwing EditorError.pathOutsideWorkspace.
  - Do not follow symlinks; a symlink whose standardized path falls outside the workspace is rejected.
  - Mirror the existing validatePathScope pattern used in the plugin API handler.
  - _Requirements: 3.7_

- [ ] 1.4 (P) Implement the in-memory fake provider for unit tests
  - Provide an actor-backed fixture that stores files in a per-instance dictionary keyed by absolute path, returning deterministic advancing mtime values so external-change tests can manipulate them explicitly.
  - Expose helpers for seeding fixture files and for rigging read, write, stat, or listDirectory to throw specific NSError values.
  - _Requirements: 14.4_

- [ ] 1.5 Unit tests for the provider layer
  - Exercise round-trip byte-exactness (files with and without trailing newlines, files containing EOF-looking sentinels) against the default provider in a per-test temp directory.
  - Exercise EditorPath scope validation against absolute, parent-traversal, and in-workspace paths.
  - Exercise the fake provider for contract parity with the default implementation (same inputs → same observable results).
  - _Requirements: 3.7, 5.7, 14.4_

- [ ] 2. EditorStore skeleton — lifecycle, state, and shared accessor

- [ ] 2.1 Define the editor store with per-sandbox state
  - Declare an @Observable @MainActor final class that owns a dictionary of per-sandbox workspace state keyed by sandbox name; each state holds open tabs in order, the active tab, tree expansion, hidden toggle, layout ratio, pane visibility, per-path stat snapshots, per-tab saved fingerprint, and per-tab tentativelyDirty flag.
  - Implement open, closeSandbox, and syncSandboxStatus; preserve workspace state for sandboxes that transition to stopped so the user can resume editing on re-entry, and garbage-collect only when a sandbox is fully removed from the sandbox store.
  - Inject the provider and toast manager at construction; do not hold references to other @Observable stores.
  - _Requirements: 1.3, 1.4, 1.5, 1.6, 4.6, 6.6, 10.2, 10.3, 13.2_

- [ ] 2.2 Expose a shared accessor for the app lifecycle hook
  - Add a lazy static shared accessor to the editor store that returns the instance configured at app init, mirroring the existing LogStore.shared pattern.
  - The adapter reads this accessor lazily at termination time; the store does not retain any reference to the adapter.
  - _Requirements: 10.7_

- [ ] 3. File browsing and opening

- [ ] 3.1 Implement workspace-rooted file tree listing
  - On first mount, enumerate the workspace root through the provider and render entries sorted directories-first then alphabetical; lazily fetch directory children on user expansion.
  - Hide entries matching standard ignore patterns by default (.git, node_modules, .DS_Store) with a user-facing toggle.
  - Show a spinner next to a directory row while its enumeration is in flight; surface enumeration failures through the toast manager without clearing prior content.
  - Render a no-workspace placeholder state when the sandbox has an empty or missing workspace path.
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8_

- [ ] 3.2 Implement file-open with size classification and binary fallback
  - Validate every candidate path through EditorPath before any I/O; reject out-of-scope paths silently with a log event.
  - Stat before reading; if size exceeds the hard cap, show a file-too-large placeholder without invoking readFile; if size exceeds the soft cap, read and open in read-only preview mode with a banner.
  - Decode as UTF-8; on decode failure, refuse editing and display a binary notice with a copy-path action.
  - De-duplicate re-opens of the same path to focus the existing tab.
  - Render a skeleton placeholder while the read is in flight and disable keyboard input for that tab until the read completes; complete the tab UI transition within 150 ms on a local filesystem while the read itself finishes asynchronously; show a pending indicator if any operation runs longer than 250 ms.
  - _Requirements: 3.1, 3.2, 3.4, 3.5, 3.6, 3.7, 11.1, 11.2, 11.3, 11.4_

- [ ] 4. Tab management, dirty pipeline, save, and summary

- [ ] 4.1 Implement multi-tab management
  - Maintain a per-sandbox ordered tab list with an active tab, per-tab scroll position, and per-tab cursor location; switching tabs restores both.
  - Close a tab subject to the unsaved guard; force-close discards edits; support Cmd+1 through Cmd+9 to activate tabs, and an overflow dropdown when the tab bar overflows.
  - Warn the user before opening a new file when the open-tab count already equals 20.
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 11.5_

- [ ] 4.2 Implement the pull-based debounced dirty pipeline
  - Accept an onBufferMutated signal from the editor buffer view (no payload) and mark the tab tentativelyDirty in O(1) time; cancel and reschedule a 500 ms idle debounce on each mutation.
  - On debounce fire, invoke the registered buffer-pull callback to read the current buffer, compute a CryptoKit SHA-256 digest, compare against the saved fingerprint, and clear tentativelyDirty when they match.
  - Accept registerBufferPull and clear the registration on tab close or external-change reload; cancel any pending debounce on tab close to avoid firing against a torn-down widget.
  - _Requirements: 4.1, 4.2, 4.3, 4.5, 11.7_

- [ ] 4.3 Implement save, save-all, external-change detection, and error surfacing
  - On Cmd+S, synchronously pull the current buffer, fingerprint it, and compare against the saved fingerprint to decide whether a write is actually needed (this flushes the debounce window on the save path).
  - Before writing, stat the path; if the mtime or size has changed against the snapshot, present the external-change dialog with Reload, Keep Mine, and Show Diff options (the diff action may be a toast stub for MVP).
  - Perform an atomic write through the provider; on success, update the saved fingerprint and the stat snapshot and flash the tab briefly in secondary color.
  - On failure, keep the tab dirty, re-enable buffer input, and surface an error toast containing the NSError localizedDescription plus domain and code.
  - Implement save-all by iterating dirty tabs sequentially and reporting per-tab results.
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 9.4, 10.4, 10.5, 10.6_

- [ ] 4.4 Implement dirtyTabsSummary with synchronous reconciliation
  - Return every tab that is either flagged tentativelyDirty or whose fingerprint differs from the saved fingerprint.
  - For tabs in tentativelyDirty state, synchronously pull the buffer and compute a fresh fingerprint before returning so the summary reflects ground truth even when the idle debounce has not yet fired.
  - Expose the summary for the close-with-dirty dialog, save-all confirmation, and the quit prompt.
  - _Requirements: 10.1, 10.7_

- [ ] 5. EditorStore unit tests
  - Cover openFile classifications (editable, read-only, too-large, binary, out-of-scope); tab lifecycle (open, activate, close, force-close, 20-tab warning); the dirty pipeline signal → debounce → reconcile → revert-to-clean; save success and failure; external-change detection with a stat mismatch; sandbox-stop state preservation and re-entry restoration; dirtyTabsSummary synchronous reconciliation within the debounce window; and closeTab cancelling pending debounces.
  - _Requirements: 14.1_

- [ ] 6. App integration and mock-workspace wiring

- [ ] 6.1 Wire the editor store into the app shell
  - Construct the editor store in the app init with a shared provider instance and the shared toast manager; inject via the SwiftUI environment.
  - Install the same instance into EditorStore.shared so the app-delegate adapter can reach it.
  - _Requirements: 13.2_

- [ ] 6.2 Add the app-delegate adapter for the quit-with-dirty prompt
  - Attach an NSApplicationDelegate via NSApplicationDelegateAdaptor; implement applicationShouldTerminate to read EditorStore.shared.dirtyTabsSummary and, when non-empty, present an NSAlert with Save All, Discard, and Cancel; proceed via terminateNow, terminateLater with save-all, or terminateCancel accordingly.
  - _Requirements: 10.7_

- [ ] 6.3 Make the mock workspace path test-configurable
  - Update the sandbox-creation sheet so that, under CLI-mock mode, the workspace path honors an SBX_CLI_MOCK_WORKSPACE environment variable while preserving the existing default when the variable is unset.
  - _Requirements: 14.3_

- [ ] 7. Editor UI components

- [ ] 7.1 Select and integrate the text-editing widget
  - Verify the minimum macOS deployment target of CodeEditorView (mchakravarty, Apache-2.0) is compatible with the project’s macOS 14 floor; if compatible, add the package to the Swift Package graph; otherwise commit to a wrapped NSTextView as the fallback, isolated to the buffer view.
  - Wire up the phase-2 syntax-highlighting feature flag so disabled builds render plain monospaced text on the dark surface and enabled builds apply the chosen grammar asynchronously without blocking input; large files bypass highlighting regardless of the flag.
  - _Requirements: 3.3, 7.1, 7.2, 7.3, 7.4, 7.5, 11.6_

- [ ] 7.2 Build the editor buffer view
  - Wrap the chosen widget to render UTF-8 text on the dark surface with a line-number gutter.
  - Register a buffer-pull callback on appear and clear it on disappear or tab close; emit onBufferMutated on every text change; disable keyboard input while the store reports the tab is loading.
  - Support standard macOS text-editing shortcuts (Cmd+Z/Shift+Z, Cmd+X/C/V, Cmd+A, arrow navigation, option-arrow word jump) and trigger save through the store on Cmd+S.
  - _Requirements: 3.2, 3.3, 4.1, 4.4, 4.5, 11.6_

- [ ] 7.3 (P) Build the file tree view
  - Render a collapsible tree rooted at the workspace with lazy expansion, per-row spinner while loading, hidden-entry toggle, and click-to-open routing through the store.
  - Attach accessibility identifiers using the relative path scheme so XCUITests can target individual rows.
  - _Requirements: 2.1, 2.3, 2.4, 2.5, 2.6_

- [ ] 7.4 (P) Build the editor tabs view
  - Render a horizontal tab bar showing one tab per open file in open-time order; show the dirty glyph and accent-colored title when the tab is dirty; flash the tab briefly in secondary color on save success.
  - Provide an overflow dropdown listing all open tabs alphabetically with dirty markers when the tab bar overflows; bind Cmd+1 through Cmd+9 to activate the corresponding tab.
  - Attach accessibility identifiers using the relative path scheme.
  - _Requirements: 4.2, 5.3, 6.1, 6.4, 6.5_

- [ ] 7.5 (P) Build the find-within-file bar
  - Reveal a find bar with input focus on Cmd+F; highlight all matches in the current buffer and display a current/total counter.
  - Navigate next on Return or Cmd+G (wrapping to start); previous on Shift+Return or Cmd+Shift+G.
  - Provide case-sensitive and whole-word toggles (both default off); dismiss with Escape, clearing highlights and returning focus to the buffer; re-run the query against the new buffer when the active tab changes.
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

- [ ] 7.6 (P) Build placeholders, banners, and confirmation dialogs
  - Implement a sandbox-status / large-file / binary banner component for inline messaging within the editor pane.
  - Implement an empty-workspace placeholder shown when the active sandbox has no workspace path.
  - Implement the unsaved-close confirmation dialog (Save / Discard / Cancel) and the external-change dialog (Reload / Keep Mine / Show Diff, the last shown as a toast stub in MVP).
  - _Requirements: 2.8, 3.4, 3.5, 10.1, 10.4_

- [ ] 8. Split-pane container and shell integration

- [ ] 8.1 Build the sandbox workspace split view
  - Compose an HSplitView-based two-pane layout with a draggable splitter; observe the measured ratio through GeometryReader and commit it to the editor store on drag-end only to avoid feedback loops.
  - Provide collapse controls for each pane that toggle pane visibility in the store; guarantee at least one pane remains visible at a time.
  - Route the single nav bar’s Dashboard and Disconnect actions through the store’s close-sandbox flow so both pick up the unsaved-close dialog when dirty tabs exist; keep the terminal view wrapped with its existing session-scoped identity so session switching behaves unchanged.
  - Leave the existing session panel available as a fallback single-pane mount when the editor pane is collapsed.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 9.1, 9.2, 9.5, 13.4_

- [ ] 8.2 Compose the editor pane layout
  - Arrange the file tree, tab bar, buffer view, find bar, and banners into the editor pane, substituting the empty-workspace placeholder when the workspace path is missing.
  - Emit structured log events for every file operation so activity surfaces in the existing debug log overlay.
  - _Requirements: 2.1, 2.8, 3.3, 10.2, 13.6_

- [ ] 8.3 Integrate the workspace view into the app shell
  - In the shell view, replace the direct mount of the session panel for running sandboxes with the new workspace view; keep the running-sandbox gate intact so the editor never mounts for non-running selections.
  - Fan the shell’s existing onChange observation over running-sandbox names into the editor store’s syncSandboxStatus call alongside the existing session and kanban calls.
  - _Requirements: 1.1, 1.5, 4.6, 6.6, 9.3, 10.2, 10.3_

- [ ] 9. Apply design-system tokens across editor views
  - Use surfaceLowest for the buffer background, surfaceContainer for the tree and tab bar, and surfaceContainerHigh for hovered rows.
  - Use accent for focus rings, the active-tab underline, and the dirty-state tab title; use secondary for the save-success flash; use error only for destructive affordances.
  - Use code font at 13 pt for buffer text, ui font at 12 pt for tab labels and tree rows, and code font at 11 pt for gutter line numbers; use the 8 pt corner radius for the find bar and floating dropdowns; avoid 1 px borders in favor of tonal surface shifts; render only dark-scheme assets.
  - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_

- [ ] 10. End-to-end test coverage

- [ ] 10.1 Build the editor UI-test base class
  - Provide an XCTestCase base class that, in setUpWithError, creates a per-test temp directory, seeds deterministic fixture files (README.md, a small source file, an ignored .git subdirectory), sets SBX_CLI_MOCK_WORKSPACE to that directory, and in tearDownWithError removes the directory.
  - _Requirements: 14.3, 14.6_

- [ ] 10.2 (P) XCUITest coverage for editor flows
  - Open a file from the tree and assert the buffer renders the seeded contents.
  - Type into the buffer, press Cmd+S, and assert the dirty indicator disappears and the toast queue is empty.
  - Switch between two tabs and assert cursor position and scroll are restored.
  - Edit without saving, press Cmd+W, and assert the unsaved-close confirmation dialog appears.
  - Edit without saving, mutate the on-disk file, attempt to save, and assert the external-change dialog appears.
  - With an empty workspace path, assert the empty-workspace placeholder is visible and the save button is absent.
  - _Requirements: 14.2_

- [ ] 10.3 (P) XCUITest coverage for sandbox-stop preservation
  - Open a file, edit it, stop the sandbox from the dashboard, confirm the dashboard becomes the current view with no crash, restart the sandbox, re-enter the session, and assert the prior tab set, active tab, and dirty state are restored.
  - _Requirements: 14.5_

- [ ] 11. Reserve the editor plugin API namespace for a future spec
  - Add editor.readState and editor.mutateState cases to the plugin permission enum without wiring any JSON-RPC handlers; document the cases as reserved for a future editor plugin spec, distinct from the existing file.read and file.write permissions.
  - _Requirements: 13.5_
