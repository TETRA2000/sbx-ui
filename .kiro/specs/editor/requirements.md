# Requirements Document

## Project Description (Input)
I'd like to create a VSCode-like editor into this app. Also, I'll integrate other features in the future.
Final UI should be like https://cmux.com/
Let's plan and create an editor feature.

## Introduction
The `editor` feature adds a VSCode-style code editor surface to sbx-ui, rendered as a split pane inside `SessionPanelView` alongside the existing terminal for a running sandbox. It lets developers browse the sandbox workspace, open files into tabs, edit with dirty-state tracking, and save changes — all without leaving the sandbox context.

File I/O goes **directly through the host filesystem** against the bind-mounted `Sandbox.workspace` path rather than through `sbx exec`. The editor is a first-party surface in sbx-ui (not an agent) and does not process untrusted prompts, so routing its reads and writes through the container boundary adds no security value while costing latency, complexity, and testability. The workspace is already a bind-mount that users routinely edit with Finder or external editors; the in-app editor is the same surface with tighter integration.

The UI style takes its cue from cmux.com (workspace-scoped split panes, agent-first ergonomics) and from the Technical Monolith design system already established in sbx-ui. This spec is explicitly foundational: it defines the editor surface so later specs can add preview panes, diff viewers, LSP, and other pane types without restructuring the shell.

## Requirements

### Requirement 1: Editor Surface and Navigation
**Objective:** As a developer, I want a code editor surface that lives next to the session terminal for a running sandbox, so that I can read and edit workspace files without leaving the sandbox context.

#### Acceptance Criteria
1. When the user opens a running sandbox and navigates into `SessionPanelView`, the Editor shall render as a split pane alongside the terminal within the detail area of `NavigationSplitView`.
2. The Editor shall default to a two-column horizontal split with the editor on the leading side and the terminal on the trailing side, separated by a draggable splitter.
3. When the user drags the splitter, the Editor shall persist the resulting split ratio keyed by sandbox name for the remainder of the app session.
4. The Editor shall provide a collapse control on each pane such that either the editor or the terminal can be hidden while the other expands to fill the detail area.
5. While no sandbox session is selected, the Editor surface shall not be mounted and shall hold no file buffers in memory.
6. When the user presses the existing "Dashboard" back button, the App shall tear down the Editor surface for that sandbox and prompt for unsaved-file confirmation as specified in Requirement 10.

### Requirement 2: Workspace File Tree
**Objective:** As a developer, I want a navigable tree of files and directories in the sandbox workspace, so that I can browse and open any file.

#### Acceptance Criteria
1. The Editor shall render a collapsible tree view rooted at `Sandbox.workspace` on the leading edge of the editor pane.
2. When the editor pane first mounts for a sandbox, the Editor shall enumerate the workspace root via `FileManager.contentsOfDirectory(at:...)` through the `EditorDocumentProvider` seam and render returned entries sorted directories-first then alphabetical.
3. When the user clicks a directory row, the Editor shall toggle its expansion state and, on first expansion, enumerate its children lazily via `EditorDocumentProvider.listDirectory`.
4. When the user clicks a file row, the Editor shall open it in a new tab per Requirement 3 or focus the existing tab if that file is already open.
5. While a directory enumeration is in flight, the Editor shall display an inline spinner next to that directory row and disable its expansion toggle.
6. Where the workspace contains entries matching standard ignore patterns (`.git`, `node_modules`, `.DS_Store`), the Editor shall hide them by default and expose a "Show hidden" toggle in the tree header.
7. If a directory enumeration fails, the Editor shall display the error via a `ToastManager` notification and leave prior tree content intact.
8. If `Sandbox.workspace` is empty or the directory does not exist on disk, the Editor shall render a "No workspace available" placeholder and disable file-open actions.

### Requirement 3: File Read and Open
**Objective:** As a developer, I want to open a file from the tree and see its contents in a text buffer, so that I can inspect or edit it.

#### Acceptance Criteria
1. When the user activates a file node, the Editor shall read the file directly from the host filesystem via `EditorDocumentProvider.readFile(path:)` (backed by `Data(contentsOf:)` against the absolute host path under `Sandbox.workspace`) and open the decoded UTF-8 contents in a new tab.
2. While a file read is in progress, the Editor shall show a skeleton placeholder in the editor pane and disable editing for that tab.
3. When the read completes, the Editor shall display the buffer using `Font.code(13)` on `Color.surfaceLowest` background with line numbers in a gutter.
4. If the file exceeds the large-file threshold defined in Requirement 11, the Editor shall open it in read-only preview mode and display a banner explaining the restriction.
5. If the file cannot be decoded as UTF-8, the Editor shall refuse to open the buffer for editing and instead display a hex/binary notice with a "Copy path" action.
6. When the user opens a file whose tab is already open, the Editor shall focus that tab instead of creating a duplicate tab.
7. If the resolved absolute path falls outside `Sandbox.workspace` (including via `..` traversal), the Editor shall reject the open request without invoking `readFile`.

### Requirement 4: Editing and Dirty State
**Objective:** As a developer, I want to type into an open file and see clear visual feedback that I have unsaved changes, so that I don't lose work.

#### Acceptance Criteria
1. When the user types, pastes, or otherwise mutates the buffer of an open file, the Editor shall mark that tab as dirty.
2. While a tab is dirty, the Editor shall display a filled circle glyph in the tab and render the tab title in `Color.accent` (#ADC6FF).
3. When the buffer is reverted to match the last-saved contents (verified by comparing a cheap content fingerprint rather than a full byte-wise compare), the Editor shall clear the dirty indicator.
4. The Editor shall support standard macOS text-editing shortcuts: Cmd+Z undo, Cmd+Shift+Z redo, Cmd+X/C/V, Cmd+A, arrow navigation, and option-arrow word jump.
5. While a file read is still in flight, the Editor shall not accept keyboard input for that tab.
6. If the sandbox transitions out of `running` while a tab is dirty, the App shall preserve the tab's buffer in `EditorStore` for the remainder of the app session so that the user can resume editing when the sandbox returns to `running`; no save is forced or blocked.

### Requirement 5: Save Semantics
**Objective:** As a developer, I want to save edited files back into the workspace, so that my changes persist and the agent sees them.

#### Acceptance Criteria
1. When the user presses Cmd+S in a dirty tab, the Editor shall write the buffer to disk via `EditorDocumentProvider.writeFile(path:contents:)` (backed by `Data.write(to:options: [.atomic])`) against the absolute host path under `Sandbox.workspace`.
2. While a save is in flight, the Editor shall render a non-blocking spinner in the tab and disable buffer editing for that tab.
3. When a save succeeds, the Editor shall clear the dirty state, update the tab's last-saved fingerprint, and surface a subtle success indication as a one-second tab flash in `Color.secondary` (#4EDEA3).
4. If a save fails (permission error, disk full, path removed externally, I/O error), the Editor shall keep the dirty state intact, show a `ToastManager` error containing the `NSError.localizedDescription`, and leave the buffer editable.
5. When the user triggers "Save All" (Cmd+Option+S), the Editor shall save every dirty tab sequentially and report any per-file failures individually.
6. The Editor shall not perform implicit auto-save; saves occur only on explicit user action.
7. The Editor shall round-trip file contents byte-for-byte (no trailing-newline insertion, no line-ending rewriting, no BOM changes); the persisted bytes on disk shall equal the decoded buffer bytes exactly.

### Requirement 6: Multi-Tab File Management
**Objective:** As a developer, I want to work with multiple open files in tabs, so that I can jump between files quickly.

#### Acceptance Criteria
1. The Editor shall render a horizontal tab bar above the editor pane showing one tab per open file, ordered by open time.
2. When the user clicks a tab, the Editor shall switch the active buffer to that file and restore its prior scroll position and cursor location.
3. When the user Cmd+Clicks a tab or presses Cmd+W, the Editor shall close that tab subject to the unsaved-guard in Requirement 10.
4. The Editor shall support Cmd+1 through Cmd+9 as shortcuts to activate the first through ninth tabs.
5. When the number of open tabs exceeds the tab-bar width, the Editor shall render a scroll region and a dropdown menu listing all open tabs sorted alphabetically with dirty-state markers.
6. The Editor shall persist the set of open tabs and the active tab keyed by sandbox name for the remainder of the app session, so re-entering `SessionPanelView` for the same sandbox restores the prior tab set.

### Requirement 7: Syntax Highlighting (Phase-2, Conditional)
**Objective:** As a developer, I want syntax-highlighted code, so that I can read files more easily.

#### Acceptance Criteria
1. Where the build is compiled with the `EDITOR_SYNTAX_HIGHLIGHTING` feature flag enabled, the Editor shall colorize open buffers using a detected language grammar.
2. Where syntax highlighting is enabled and the file extension is recognized, the Editor shall apply the corresponding grammar and render tokens using the chosen highlight palette consistent with the dark design system.
3. Where syntax highlighting is enabled and the file extension is not recognized, the Editor shall render the buffer in plain monospaced text identical to the flag-disabled build.
4. Where syntax highlighting is disabled at build time, the Editor shall render every buffer as plain monospaced text using `Font.code(13)` on `Color.surfaceLowest`.
5. While a file exceeds the large-file threshold defined in Requirement 11, the Editor shall bypass syntax highlighting regardless of the feature flag.

### Requirement 8: Find Within File
**Objective:** As a developer, I want to search for text within the current file and jump between matches, so that I can navigate large files quickly.

#### Acceptance Criteria
1. When the user presses Cmd+F in the active editor tab, the Editor shall reveal a find bar at the top of the editor pane with input focus.
2. When the user types into the find bar, the Editor shall highlight all matches in the current buffer and display a `<current>/<total>` counter.
3. When the user presses Return or Cmd+G in the find bar, the Editor shall scroll to and focus the next match, wrapping to the start after the last match.
4. When the user presses Shift+Return or Cmd+Shift+G, the Editor shall navigate to the previous match.
5. The Editor shall support case-sensitive and whole-word toggles in the find bar; both default to off.
6. When the user presses Escape in the find bar, the Editor shall clear highlights and return focus to the buffer.
7. Where the find bar is visible and the buffer is switched to a different tab, the Editor shall re-run the current query against the new buffer.

### Requirement 9: Integration with Session Terminal
**Objective:** As a developer, I want the editor and terminal to share a coherent per-sandbox context, so that I can switch between typing commands and editing files without losing state.

#### Acceptance Criteria
1. The Editor and the `TerminalViewWrapper` in `SessionPanelView` shall be siblings within the same sandbox-scoped detail view and shall not conflict for keyboard focus; clicking either pane shall transfer focus to that pane only.
2. When the user triggers "Disconnect" on the terminal from `SessionPanelView`, the App shall additionally prompt to close the Editor surface if any tab is dirty, and otherwise tear the Editor down with the terminal.
3. While a sandbox is in `running` status, the App shall allow both the agent PTY (`TerminalSessionStore`) and the Editor's host file I/O to operate independently; because file I/O is direct host access and does not share a transport with the PTY, the two paths do not contend.
4. When the agent writes to a file that the user has currently open, the Editor shall handle the external change per Requirement 10; the terminal stream itself shall be unmodified.
5. The Editor shall not send any input to the terminal PTY; conversely, the terminal shall not invoke file I/O through `EditorDocumentProvider`.

### Requirement 10: Error Handling and Edge States
**Objective:** As a developer, I want clear, non-destructive behavior when things go wrong, so that I don't lose work or get stuck in an inconsistent state.

#### Acceptance Criteria
1. When the user attempts to close a tab or the Editor while any tab is dirty, the Editor shall present a confirmation dialog with choices "Save", "Discard", and "Cancel".
2. If the sandbox transitions from `running` to any other status while files are open, the App shall unmount the Editor as part of the normal `SessionPanelView` teardown (per `ShellView` gating) while preserving all buffers in `EditorStore`; no additional banner or save-blocking dialog is presented.
3. When the user re-enters `SessionPanelView` for the same sandbox (on return to `running`), the Editor shall restore the previously open tabs, active tab, scroll positions, and dirty buffers from `EditorStore`.
4. Where an open file is modified outside the Editor (detected by a mtime or size mismatch on the next read or save attempt via `EditorDocumentProvider.stat`), the Editor shall present a three-way choice: "Reload from disk", "Keep mine and overwrite on save", and "Show diff"; the "Show diff" option may be stubbed as a toast in MVP and implemented later.
5. If a read fails mid-session, the Editor shall keep any already-open tabs intact and surface the error via `ToastManager` without closing other tabs.
6. If an `EditorDocumentProvider` call throws an `NSError` (permission denied, file not found, disk full, I/O error), the Editor shall include `localizedDescription` and the underlying error domain/code in the user-facing error toast.
7. When the App is about to quit with any dirty Editor tab, the App shall prompt once with a summary of dirty files before allowing termination.

### Requirement 11: Performance and Large-File Behavior
**Objective:** As a developer, I want the editor to stay responsive on the range of files I'd realistically open, and to refuse to open files that would freeze the UI.

#### Acceptance Criteria
1. The Editor shall classify any file larger than 2 MB or longer than 50,000 lines as a "large file" and open it in read-only preview mode per Requirement 3.4.
2. The Editor shall classify any file larger than 20 MB as "not openable" and shall not invoke `readFile` against it; instead it shall show a "File too large" placeholder with path and size, using only the `stat` result.
3. When opening a file of any size, the Editor shall complete the UI transition to the tab within 150ms on a local host filesystem; the read itself may complete asynchronously.
4. While any file operation (read, write, listDirectory, stat) is in flight for longer than 250ms, the Editor shall surface a visible pending indicator so the user sees progress.
5. The Editor shall keep total open-buffer memory bounded; when more than 20 tabs are open, the Editor shall warn the user before opening an additional file.
6. Where syntax highlighting is enabled per Requirement 7, the Editor shall tokenize asynchronously and shall not block keyboard input while a tokenization pass runs.
7. Dirty-state comparison per Requirement 4.3 shall run in O(1) amortized time per keystroke by comparing a content fingerprint rather than performing a byte-wise equality check against the last-saved buffer.

### Requirement 12: Design System Consistency
**Objective:** As a developer, I want the editor to look and feel like the rest of sbx-ui, so that it integrates visually and behaviorally with existing surfaces.

#### Acceptance Criteria
1. The Editor shall use `Color.surfaceLowest` (#0E0E0E) for the buffer background, `Color.surfaceContainer` for the tree and tab bar, and `Color.surfaceContainerHigh` for hovered rows.
2. The Editor shall use `Color.accent` (#ADC6FF) for focus rings, the active-tab underline, and dirty-state tab titles.
3. The Editor shall use `Font.code(13)` for all buffer text, `Font.ui(12)` for tab labels and tree rows, and `Font.code(11)` for gutter line numbers.
4. The Editor shall use the 8pt corner radius from `DesignSystem/Constants.swift` for the find bar and any floating dropdowns and shall avoid 1px borders in favor of tonal surface shifts, matching the Technical Monolith system described in the sbx-ui spec.
5. The Editor shall match the dark color scheme enforced by `.preferredColorScheme(.dark)` in `ShellView` and shall not render any light-mode-only assets.

### Requirement 13: Extensibility Hooks for Future Integrations
**Objective:** As a developer, I want the editor architecture to accommodate future panes and capabilities (preview, diff, LSP, notebooks) without rewrites, so that subsequent Kiro specs can bolt in cleanly.

#### Acceptance Criteria
1. The App shall define `EditorDocumentProvider` as the protocol boundary through which the editor obtains file contents, decoupling `EditorStore` from the underlying I/O mechanism.
2. The App shall define an `EditorStore` as an `@Observable @MainActor` type, injected via `.environment()` in `sbx_uiApp.swift`, following the existing store pattern used by `SandboxStore`, `TerminalSessionStore`, and `PolicyStore`.
3. The App shall provide a default `FileManager`-backed `EditorDocumentProvider` implementation and allow alternative providers (for example, a future remote-sandbox read/write provider, or a read-only archive provider) to be registered without changes to `EditorStore`.
4. The Editor split-pane layout shall be implemented as an N-pane container that accepts arbitrary pane types (editor, terminal, future preview, future diff) so that additional panes can be added in later specs without restructuring `SessionPanelView`.
5. Where a future plugin integration needs to observe or mutate editor state, the App shall expose a minimal `EditorPluginApi` surface (open file, close file, get dirty tabs) extending the existing `PluginApiHandler` pattern, with its own permission namespace (`editor.readState`, `editor.mutateState`) distinct from the existing `file.read` / `file.write` plugin permissions.
6. The Editor shall emit structured log events to `LogStore.shared` for every file operation so that the existing debug log overlay in `ShellView` can surface editor activity.

### Requirement 14: Testing Coverage
**Objective:** As a developer, I want unit and E2E test coverage for the editor so that regressions are caught automatically, matching the pattern of existing specs.

#### Acceptance Criteria
1. The App shall provide Swift Testing unit tests in `sbx-uiTests/` for `EditorStore` covering tab open/close, dirty-state transitions, save success path, save failure path, unsaved-close guard, external-change detection, and large-file classification.
2. The App shall provide XCUITest coverage in `sbx-uiUITests/` using `SBX_CLI_MOCK=1` and `tools/mock-sbx` that asserts opening a file from the tree, editing and saving a file, switching between tabs, and closing a dirty tab triggers the confirmation dialog.
3. The App shall isolate E2E test workspaces under a per-test temporary directory (pointed to by `Sandbox.workspace`) so that tests never read or mutate real user files outside the temp directory; no changes to `tools/mock-sbx` are required for file I/O, since the editor does not route through `sbx exec`.
4. The App shall provide a `FakeEditorDocumentProvider` test fixture backed by an in-memory dictionary so that `EditorStore` unit tests do not touch the filesystem.
5. When an E2E test simulates a sandbox transition from running to stopped mid-edit, it shall verify that the Editor unmounts with the `SessionPanelView`, buffers are preserved in `EditorStore`, and a subsequent re-entry restores the prior tab set and dirty state.
6. The App shall keep `sbx-uiUITests` deterministic by using per-test temporary workspace directories created in `setUpWithError` and torn down in `tearDownWithError`; no test shall rely on fixture files outside its own temp directory.
